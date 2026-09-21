import 'dart:async';
import 'dart:math';
import 'dart:ui' show Rect;
import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:geolocator/geolocator.dart';
import 'package:path_provider/path_provider.dart';
import '../../config/env.dart';
import '../../utils/http/api_exception.dart';
import '../../services/camera_capture_controller.dart';
import '../../services/face_embedding_service.dart';
import '../../services/face_similarity.dart';
import '../../services/liveness/camera_frame.dart';
import '../../services/liveness/face_observation.dart';
import '../../services/liveness/liveness_analyzer.dart';
import '../../services/liveness/liveness_coach.dart';
import '../../services/liveness/liveness_identity.dart';
import '../../services/liveness/liveness_session.dart';
import '../../models/face_match_result.dart';
import '../../services/staff_service.dart';
import '../../services/attendance_service.dart';
import './mark_attendance_state.dart';

/// Where the phone is, as the attendance record needs it.
typedef Locator = Future<({double latitude, double longitude})> Function();

/// Drives the whole "mark attendance" flow.
///
/// The person is asked to turn their head left and right (in a random order,
/// then look straight) while the live camera is watched ([onFrame]). Frames from
/// that check itself — before the turns, at each turn, and at the end — are
/// kept, so the person who is recorded is the person who did the turns: the
/// final frame must match their enrolled faces (fetched fresh from the backend,
/// so a re-enrolment takes effect immediately) and the others must be the same
/// face as it. Only then are location and time captured and the record
/// uploaded. Nothing is recorded unless all of that holds — enforced here, and
/// the backend never re-derives it, so this cubit is the only place that
/// decision gets made.
///
/// A check that fails lets the person try again with a new random challenge, as
/// often as they need; every failure is reported to the backend for review.
/// Recoverable trouble (no network, location off…) drops back to a fresh check
/// with a message; only "the camera itself won't open" uses
/// [MarkAttendanceStatus.error].
class MarkAttendanceCubit extends Cubit<MarkAttendanceState> {
  MarkAttendanceCubit({
    required String staffId,
    required CameraCaptureController camera,
    required FaceEmbeddingService embeddingService,
    required StaffService staffService,
    required AttendanceService attendanceService,
    this.finalFrames = 5,
    bool? framesMirrored,
    Random? random,
    Locator? locate,
    Future<String> Function()? newPhotoPath,
    DateTime Function()? clock,
  }) : _staffId = staffId,
       _camera = camera,
       _embeddingService = embeddingService,
       _staffService = staffService,
       _attendanceService = attendanceService,
       _framesMirrored = framesMirrored ?? Env.livenessFramesMirrored,
       _random = random ?? Random(),
       _locate = locate ?? _currentPosition,
       _newPhotoPath = newPhotoPath ?? _defaultPhotoPath,
       _clock = clock ?? DateTime.now,
       super(const MarkAttendanceState()) {
    _startAttempt();
  }

  final String _staffId;
  final CameraCaptureController _camera;
  final FaceEmbeddingService _embeddingService;
  final StaffService _staffService;
  final AttendanceService _attendanceService;
  final bool _framesMirrored;
  final Random _random;
  final Locator _locate;
  final Future<String> Function() _newPhotoPath;
  final DateTime Function() _clock;

  /// How many of the last frames of the final look-straight are embedded and averaged. One live
  /// frame is noisy (a still of the same face scores 0.85+, a single video frame 0.5-0.8).
  final int finalFrames;

  late LivenessSession _session;
  late LivenessCoach _coach;
  final Map<String, _KeptFrame> _kept = {};
  final List<_KeptFrame> _recentStraight = [];

  /// What to show the person right now (prompt, turn line, ring, message).
  late final ValueNotifier<LivenessGuidance> guidance = ValueNotifier(_coach.idle());

  Timer? _watchdog;
  DateTime? _lastFrameAt;
  Duration _lastObservationAt = Duration.zero;
  DateTime? _passedAt;

  /// The turns being asked for in this attempt, in order.
  List<TurnSide> get challenge => _session.challenge;

  /// Exposed so the view can hand the underlying [CameraController] to a
  /// [CameraPreview] widget — the cubit doesn't hold any UI itself.
  CameraCaptureController get camera => _camera;

  Future<void> initializeCamera() async {
    emit(const MarkAttendanceState());
    try {
      await _camera.initialize();
      _watchdog ??= Timer.periodic(const Duration(milliseconds: 500), (_) => _checkForStall());
      emit(const MarkAttendanceState(status: MarkAttendanceStatus.cameraReady));
    } catch (_) {
      emit(
        MarkAttendanceState(
          status: MarkAttendanceStatus.error,
          errorMessage: 'Could not open the camera. Check that camera access is allowed for this app.',
        ),
      );
    }
  }

  /// One analysed frame from the live preview.
  void onFrame(AnalyzedFrame frame) {
    if (state.status != MarkAttendanceStatus.cameraReady || _session.isFinished) return;

    final observation = frame.observation;
    _lastFrameAt = _clock();
    _lastObservationAt = observation.at;

    final keep = _session.onObservation(observation);
    if (keep != null) _keepFrame(keep, frame);
    _trackStraight(frame);
    guidance.value = _coach.coach(observation);
    _react();
  }

  /// Start a new check after a failure.
  void retry() {
    _startAttempt();
    emit(const MarkAttendanceState(status: MarkAttendanceStatus.cameraReady));
  }

  // ---- the check ------------------------------------------------------------

  void _startAttempt() {
    _session = LivenessSession.random(_random);
    _coach = LivenessCoach(_session);
    _kept.clear();
    _recentStraight.clear();
    _lastFrameAt = null;
    _passedAt = null;
    if (!isClosed) guidance.value = _coach.idle();
  }

  /// Keeps the frames the identity rule needs: the start frame, the best frame of
  /// each turn (replaced whenever a better one comes), and the final frame.
  void _keepFrame(KeepFrame keep, AnalyzedFrame frame) {
    final box = frame.faceBox;
    final copy = frame.snapshot();
    if (box == null || copy == null) return;

    final key = switch (keep.role) {
      FrameRole.start => 'start',
      FrameRole.turnPeak => 'turn${keep.turnIndex}',
      FrameRole.finalStraight => 'final',
    };
    _kept[key] = _KeptFrame(copy, box);
  }

  /// While the person holds still at the end, remembers the last few frames so they can all be used.
  void _trackStraight(AnalyzedFrame frame) {
    final phase = _session.phase;
    if (phase == LivenessPhase.lookStraight && _session.holdProgress == 0) {
      _recentStraight.clear(); // not (or no longer) holding still
      return;
    }
    if (phase != LivenessPhase.lookStraight && phase != LivenessPhase.passed) return;

    final box = frame.faceBox;
    final copy = frame.snapshot();
    if (box == null || copy == null) return;
    _recentStraight.add(_KeptFrame(copy, box));
    if (_recentStraight.length > finalFrames) _recentStraight.removeAt(0);
  }

  void _react() {
    switch (_session.phase) {
      case LivenessPhase.passed:
        _passedAt = _clock();
        unawaited(_verifyAndRecord());
      case LivenessPhase.failed:
        _failed(LivenessCoach.messageForFailure(_session.failure!), reason: _session.failure!.name);
      case LivenessPhase.waitingForFace:
      case LivenessPhase.holdStill:
      case LivenessPhase.turning:
      case LivenessPhase.lookStraight:
        break;
    }
  }

  /// If the camera stops delivering frames, the check must still time out rather than hang.
  void _checkForStall() {
    if (state.status != MarkAttendanceStatus.cameraReady || _session.isFinished) return;
    final last = _lastFrameAt;
    if (last == null) return;
    final silent = _clock().difference(last);
    if (silent < const Duration(seconds: 1)) return;

    _session.onTick(_lastObservationAt + silent);
    _react();
  }

  // ---- verifying and recording ---------------------------------------------

  Future<void> _verifyAndRecord() async {
    emit(const MarkAttendanceState(status: MarkAttendanceStatus.processing));
    try {
      // The staff member's profile is fetched while their frames are being read.
      final staffFuture = _staffService.getById(_staffId);

      final start = _kept['start'];
      final turns = [for (var i = 0; i < _session.totalTurns; i++) _kept['turn$i']];
      final end = _kept['final'];
      if (start == null || end == null || turns.any((t) => t == null)) {
        _failed('The camera did not give a clear picture. Please try again.', reason: 'missingFrames');
        return;
      }

      final photoPath = await _newPhotoPath();
      final others = <List<double>>[];
      for (final frame in [start, ...turns.cast<_KeptFrame>()]) {
        others.add((await _embed(frame)).embedding);
      }

      // The last few frames of the look-straight, averaged; the very last one is the attendance photo.
      final finals = _recentStraight.isEmpty ? [end] : List.of(_recentStraight);
      final finalEmbeddings = <List<double>>[];
      for (var i = 0; i < finals.length; i++) {
        final isLast = i == finals.length - 1;
        finalEmbeddings.add((await _embed(finals[i], saveJpegTo: isLast ? photoPath : null)).embedding);
      }
      final finalSample = FaceSample(embedding: averageEmbeddings(finalEmbeddings), imagePath: photoPath);

      final staff = await staffFuture;
      // Only templates made by this build's face model are comparable.
      final templates = staff.embeddingsFor(Env.faceModelVersion);
      if (templates.isEmpty) {
        throw FaceProcessingException(
          staff.faceTemplates.isEmpty
              ? 'Your face hasn\'t been enrolled yet. Contact your admin.'
              : 'Your face needs to be enrolled again for this version of the app. Contact your admin.',
        );
      }

      final identity = evaluateLivenessIdentity(
        finalEmbedding: finalSample.embedding,
        otherEmbeddings: others,
        templates: templates,
        matchThreshold: Env.faceMatchThreshold,
        sameFaceMin: Env.enrolmentMinSimilarity,
        expectedOthers: 1 + _session.totalTurns,
      );
      if (!kReleaseMode) await _logIdentity(identity, finals.last, templates, finalEmbeddings, finalSample);

      switch (identity.failure) {
        case null:
          break;
        case IdentityFailure.noMatch:
          _failed('', similarity: identity.similarityToEnrolled, matchFailure: true);
          return;
        case IdentityFailure.differentPerson:
          _failed('The face changed during the check. Only you should be in the picture.', reason: 'differentPerson');
          return;
        case IdentityFailure.missingFrames:
          _failed('The camera did not give a clear picture. Please try again.', reason: 'missingFrames');
          return;
      }

      final position = await _locate();
      final result = _session.result!;

      await _attendanceService.record(
        staffId: _staffId,
        selfiePath: photoPath,
        latitude: position.latitude,
        longitude: position.longitude,
        matchConfidence: identity.similarityToEnrolled,
        capturedAt: _passedAt ?? _clock(),
        liveness: {
          'version': 1,
          'challenge': [for (final side in result.challenge) side.name],
          'durationMs': result.duration.inMilliseconds,
          'peakYaws': [for (final v in result.peakYaws) double.parse(v.toStringAsFixed(1))],
          'peakTurnRatios': [for (final v in result.peakTurnRatios) double.parse(v.toStringAsFixed(3))],
          'baselineYaw': double.parse(result.baselineYaw.toStringAsFixed(1)),
          'baselineRatio': double.parse(result.baselineRatio.toStringAsFixed(3)),
          'sameFaceMin': identity.lowestSameFace == null
              ? null
              : double.parse(identity.lowestSameFace!.toStringAsFixed(3)),
        },
      );

      emit(MarkAttendanceState(status: MarkAttendanceStatus.success, similarity: identity.similarityToEnrolled));
    } on FaceProcessingException catch (e) {
      _backToCamera(e.message);
    } on ApiException catch (e) {
      _backToCamera(e.message);
    } on TimeoutException {
      _backToCamera('Could not get your location. Move to an open area and try again.');
    } catch (e) {
      if (!kReleaseMode) debugPrint('[attendance] unexpected error: $e');
      _backToCamera('Something went wrong. Please try again.');
    }
  }

  Future<FaceSample> _embed(_KeptFrame kept, {String? saveJpegTo}) =>
      _embeddingService.embedFrame(kept.frame, kept.box, framesMirrored: _framesMirrored, saveJpegTo: saveJpegTo);

  /// Debug builds only: how each of the final frames scored against the enrolled faces, and how
  /// their average did, so the effect of averaging can be seen; plus how the last frame would have
  /// scored the other way round (the quickest check that a device's mirroring is what we assume;
  /// embeddings are nearly flip-proof, so the two usually differ by little).
  Future<void> _logIdentity(
    LivenessIdentityResult identity,
    _KeptFrame last,
    List<List<double>> templates,
    List<List<double>> finalEmbeddings,
    FaceSample averaged,
  ) async {
    double best(List<double> e) => templates.map((t) => cosineSimilarity(t, e)).reduce(max);
    try {
      final other = await _embeddingService.embedFrame(last.frame, last.box, framesMirrored: !_framesMirrored);
      final perFrame = finalEmbeddings.map((e) => best(e).toStringAsFixed(3)).join(', ');
      debugPrint(
        '[attendance] identity: frames [$perFrame] -> averaged ${best(averaged.embedding).toStringAsFixed(3)} '
        '(mirrored=$_framesMirrored; last frame the other way round ${best(other.embedding).toStringAsFixed(3)}); '
        'lowest same-face ${identity.lowestSameFace?.toStringAsFixed(3)}; failure=${identity.failure?.name}',
      );
    } catch (e) {
      debugPrint('[attendance] identity log failed: $e');
    }
  }

  // ---- outcomes ---------------------------------------------------------------

  /// A check that did not pass: the person can try again as often as they like.
  void _failed(String message, {double? similarity, bool matchFailure = false, String? reason}) {
    if (isClosed) return;
    if (!kReleaseMode) {
      debugPrint(
        '[attendance] failed: ${matchFailure ? 'no_match' : 'liveness_failed'} reason=$reason '
        'challenge=${_session.challenge.map((side) => side.name).join(',')} turnsDone=${_session.turnsCompleted} '
        'phase=${_session.phase.name} similarity=${similarity?.toStringAsFixed(3)}',
      );
    }
    emit(
      MarkAttendanceState(
        status: matchFailure ? MarkAttendanceStatus.matchFailed : MarkAttendanceStatus.livenessFailed,
        similarity: similarity,
        errorMessage: message,
      ),
    );

    // Let the backend know, so failures can be reviewed. It must never change what the person sees.
    unawaited(
      _attendanceService
          .reportFailedAttempt(outcome: matchFailure ? 'no_match' : 'liveness_failed', reason: reason)
          .catchError((_) {}),
    );
  }

  /// Trouble that is not the person's fault (network, location…): straight back to a fresh check.
  void _backToCamera(String message) {
    if (isClosed) return;
    _startAttempt();
    emit(MarkAttendanceState(status: MarkAttendanceStatus.cameraReady, errorMessage: message));
  }

  @override
  Future<void> close() async {
    _watchdog?.cancel();
    guidance.dispose();
    await _camera.dispose();
    return super.close();
  }

  // ---- platform defaults ------------------------------------------------------

  static Future<String> _defaultPhotoPath() async {
    final dir = await getTemporaryDirectory();
    return '${dir.path}/attendance_${DateTime.now().microsecondsSinceEpoch}.jpg';
  }

  static Future<({double latitude, double longitude})> _currentPosition() async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      throw FaceProcessingException('Location services are off. Turn them on to mark attendance.');
    }

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
      throw FaceProcessingException('Location permission is required to mark attendance.');
    }

    final position = await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, timeLimit: Duration(seconds: 15)),
    );
    return (latitude: position.latitude, longitude: position.longitude);
  }
}

/// A frame kept from the check, with where the face is on it.
class _KeptFrame {
  const _KeptFrame(this.frame, this.box);

  final CameraFrame frame;
  final Rect box;
}
