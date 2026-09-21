import 'dart:ui' show Rect;
import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../config/env.dart';
import '../../services/camera_capture_controller.dart';
import '../../services/face_embedding_service.dart';
import '../../services/face_similarity.dart';
import '../../services/liveness/camera_frame.dart';
import '../../services/liveness/enrolment_pose_guide.dart';
import '../../services/liveness/face_observation.dart';
import '../../services/liveness/liveness_analyzer.dart';
import '../../models/face_match_result.dart';
import './face_capture_state.dart';

/// Drives the capture → detect → embed flow used by the enrolment screen, which
/// takes several photos of the same person (straight, then a little to each
/// side) so matching later copes with a small change of angle or light.
///
/// Nobody presses a shutter: the live pose is watched ([onObservation]) and each
/// photo is taken by itself once the face is in the oval and held at the pose
/// asked for. The photo actually taken is then checked again, in case the person
/// moved.
///
/// The template stored for each photo is not the still's embedding but the average
/// of the last few frames of the live stream from the hold — the same kind of
/// picture the attendance check later compares against. The same face scores about
/// 0.2 lower between a still and a stream frame than between two stream frames,
/// so templates made from stills reject the person they belong to. (The mark-attendance screen has its own cubit — it needs the same
/// capture+embed steps plus a comparison against fetched embeddings and an
/// upload afterwards, which doesn't fit this cubit's single-purpose shape.)
class FaceCaptureCubit extends Cubit<FaceCaptureState> {
  FaceCaptureCubit(
    this._camera,
    this._embeddingService, {
    this.targetShots = Env.enrolmentShots,
    EnrolmentPoseGuide? guide,
    this.streamFrames = 5,
    bool? framesMirrored,
  }) : _framesMirrored = framesMirrored ?? Env.livenessFramesMirrored,
       guide = guide ?? EnrolmentPoseGuide(plan: _planFor(targetShots)),
       super(const FaceCaptureState()) {
    guidance = ValueNotifier(this.guide.idle());
  }

  final CameraCaptureController _camera;
  final FaceEmbeddingService _embeddingService;

  /// How many photos complete an enrolment.
  final int targetShots;

  /// Decides when each photo is taken.
  final EnrolmentPoseGuide guide;

  /// How many of the last frames of the hold go into a photo's template (0 keeps the still's embedding).
  final int streamFrames;
  final bool _framesMirrored;

  /// The last frames seen while the pose was being held steadily, with where the face was on each.
  final List<_HeldFrame> _held = [];

  /// What to show the person right now (prompt, turn meter, message).
  late final ValueNotifier<PoseGuidance> guidance;

  static List<EnrolmentPose> _planFor(int shots) => [
    for (var i = 0; i < shots; i++) EnrolmentPose.values[i % EnrolmentPose.values.length],
  ];

  /// Exposed so the view can hand the underlying [CameraController] to a
  /// [CameraPreview] widget — the cubit doesn't hold any UI itself.
  CameraCaptureController get camera => _camera;

  Future<void> initializeCamera() async {
    try {
      await _camera.initialize();
      emit(state.copyWith(status: FaceCaptureStatus.cameraReady));
    } catch (_) {
      emit(
        state.copyWith(
          status: FaceCaptureStatus.error,
          errorMessage: 'Could not open the camera. Check camera permission.',
        ),
      );
    }
  }

  /// One analysed frame from the live preview, picture included: the last few of a hold are
  /// kept for the template. Otherwise the same as [onObservation].
  void onFrame(AnalyzedFrame frame) => onObservation(frame.observation, frame: frame);

  /// One analysed frame from the live preview. Updates the guidance and, once
  /// the pose has been held long enough, takes the photo.
  void onObservation(FaceObservation observation, {AnalyzedFrame? frame}) {
    if (state.status != FaceCaptureStatus.cameraReady) return;

    final next = guide.onObservation(observation);
    guidance.value = next;
    if (frame != null && streamFrames > 0) _remember(frame, next);
    if (next.shouldCapture) {
      if (!kReleaseMode) debugPrint('[enrol] auto-capture ${next.pose.name} (photo ${next.shotIndex + 1})');
      captureAndProcess();
    }
  }

  /// Keeps the frames of a steady hold; a broken or restarted hold throws them away.
  void _remember(AnalyzedFrame frame, PoseGuidance next) {
    if (!next.inPosition || next.holdProgress == 0) {
      _held.clear();
      return;
    }
    final box = frame.faceBox;
    final copy = frame.snapshot();
    if (box == null || copy == null) return;
    _held.add(_HeldFrame(copy, box));
    if (_held.length > streamFrames) _held.removeAt(0);
  }

  /// The photo's template from the frames of the hold, or [still] itself when there are none
  /// (or they can't be read): the enrolment goes on either way.
  Future<FaceSample> _withStreamEmbedding(FaceSample still, List<_HeldFrame> frames) async {
    if (frames.isEmpty) return still;
    try {
      final embeddings = <List<double>>[];
      for (final held in frames) {
        final sample = await _embeddingService.embedFrame(held.frame, held.box, framesMirrored: _framesMirrored);
        embeddings.add(sample.embedding);
      }
      final template = averageEmbeddings(embeddings);
      if (!kReleaseMode) {
        debugPrint(
          '[enrol] template from ${frames.length} stream frames; '
          'against the still ${cosineSimilarity(template, still.embedding).toStringAsFixed(3)}',
        );
      }
      return FaceSample(
        embedding: template,
        imagePath: still.imagePath,
        yawDegrees: still.yawDegrees,
        faceCenterX: still.faceCenterX,
        faceCenterY: still.faceCenterY,
        faceWidthRatio: still.faceWidthRatio,
      );
    } catch (e) {
      if (!kReleaseMode) debugPrint('[enrol] stream template failed, keeping the still: $e');
      return still;
    }
  }

  Future<void> captureAndProcess() async {
    emit(state.copyWith(status: FaceCaptureStatus.processing));
    final frames = List<_HeldFrame>.of(_held);
    _held.clear();
    try {
      final photo = await _camera.capture();
      final still = await _embeddingService.generateEmbedding(photo.path, maxYawDegrees: guide.maxStillYaw);

      // The person may have moved (or left the oval) between the trigger and the shutter.
      final problem = guide.stillProblem(
        yawDegrees: still.yawDegrees,
        centerX: still.faceCenterX,
        centerY: still.faceCenterY,
        widthRatio: still.faceWidthRatio,
      );
      if (problem != null) {
        if (!kReleaseMode) {
          debugPrint(
            '[enrol] photo rejected (${guide.pose.name}): yaw ${still.yawDegrees}, '
            'face x ${still.faceCenterX} y ${still.faceCenterY} w ${still.faceWidthRatio}',
          );
        }
        throw FaceProcessingException(problem);
      }

      final sample = await _withStreamEmbedding(still, frames);

      // Every photo of one enrolment must be the same person; a much lower
      // score against the first photo means someone else stepped in or the
      // shot is bad.
      if (state.shots.isNotEmpty) {
        final similarity = _embeddingService.compare(state.shots.first.embedding, sample.embedding).similarity;
        if (similarity < Env.enrolmentMinSimilarity) {
          throw FaceProcessingException(
            "That doesn't look like the same person as the first photo. Please retake this photo.",
          );
        }
      }

      final shots = [...state.shots, sample];
      guide.shotAccepted();
      if (!kReleaseMode) debugPrint('[enrol] photo accepted (${shots.length}/$targetShots) yaw ${sample.yawDegrees}');
      guidance.value = guide.idle();
      emit(
        state.copyWith(
          status: shots.length >= targetShots ? FaceCaptureStatus.ready : FaceCaptureStatus.cameraReady,
          shots: shots,
        ),
      );
    } on FaceProcessingException catch (e) {
      guide.shotRejected();
      emit(state.copyWith(status: FaceCaptureStatus.cameraReady, errorMessage: e.message));
    } catch (_) {
      guide.shotRejected();
      emit(
        state.copyWith(
          status: FaceCaptureStatus.cameraReady,
          errorMessage: 'Something went wrong capturing the photo. Try again.',
        ),
      );
    }
  }

  /// Throws away every photo and starts the enrolment again from the first.
  void retake() {
    guide.reset();
    guidance.value = guide.idle();
    emit(const FaceCaptureState(status: FaceCaptureStatus.cameraReady));
  }

  @override
  Future<void> close() async {
    guidance.dispose();
    await _camera.dispose();
    return super.close();
  }
}

class _HeldFrame {
  const _HeldFrame(this.frame, this.box);

  final CameraFrame frame;
  final Rect box;
}
