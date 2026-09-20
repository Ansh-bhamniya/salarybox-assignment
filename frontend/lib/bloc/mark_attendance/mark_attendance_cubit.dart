import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:geolocator/geolocator.dart';
import '../../utils/http/api_exception.dart';
import '../../services/camera_capture_controller.dart';
import '../../services/face_embedding_service.dart';
import '../../models/face_match_result.dart';
import '../../services/staff_service.dart';
import '../../services/attendance_service.dart';
import './mark_attendance_state.dart';

/// Drives the whole "tap Mark Attendance" flow: capture selfie → detect and
/// embed the face → compare against the staff member's own enrolled
/// embedding (fetched fresh from the backend, not cached from login, so a
/// re-enrolment takes effect immediately) → on match, capture location and
/// upload. Nothing is recorded unless the face matches — enforced here
/// client-side and, independently, the backend never re-derives a match on
/// its own, so this cubit is the only place that decision gets made.
///
/// Recoverable failures (no face, no network, location off…) drop the user
/// back on the live camera with a message rather than a dead-end screen;
/// only "the camera itself won't open" uses [MarkAttendanceStatus.error].
class MarkAttendanceCubit extends Cubit<MarkAttendanceState> {
  MarkAttendanceCubit({
    required String staffId,
    required CameraCaptureController camera,
    required FaceEmbeddingService embeddingService,
    required StaffService staffService,
    required AttendanceService attendanceService,
  }) : _staffId = staffId,
       _camera = camera,
       _embeddingService = embeddingService,
       _staffService = staffService,
       _attendanceService = attendanceService,
       super(const MarkAttendanceState());

  final String _staffId;
  final CameraCaptureController _camera;
  final FaceEmbeddingService _embeddingService;
  final StaffService _staffService;
  final AttendanceService _attendanceService;

  /// Exposed so the view can hand the underlying [CameraController] to a
  /// [CameraPreview] widget — the cubit doesn't hold any UI itself.
  CameraCaptureController get camera => _camera;

  Future<void> initializeCamera() async {
    emit(const MarkAttendanceState());
    try {
      await _camera.initialize();
      emit(const MarkAttendanceState(status: MarkAttendanceStatus.cameraReady));
    } catch (_) {
      emit(
        const MarkAttendanceState(
          status: MarkAttendanceStatus.error,
          errorMessage: 'Could not open the camera. Check that camera access is allowed for this app.',
        ),
      );
    }
  }

  Future<void> markAttendance() async {
    emit(const MarkAttendanceState(status: MarkAttendanceStatus.processing));
    try {
      // Capture first so the shot is the moment the user pressed the
      // shutter, not after a network round-trip.
      final photo = await _camera.capture();
      final capturedAt = DateTime.now();

      final sample = await _embeddingService.generateEmbedding(photo.path);

      final staff = await _staffService.getById(_staffId);
      final enrolledEmbedding = staff.faceEmbedding;
      if (enrolledEmbedding == null) {
        throw FaceProcessingException('Your face hasn\'t been enrolled yet. Contact your admin.');
      }

      final result = _embeddingService.compare(enrolledEmbedding, sample.embedding);

      if (!result.isMatch) {
        emit(MarkAttendanceState(status: MarkAttendanceStatus.matchFailed, similarity: result.similarity));
        return;
      }

      final position = await _currentPosition();

      await _attendanceService.record(
        staffId: _staffId,
        selfiePath: sample.imagePath,
        latitude: position.latitude,
        longitude: position.longitude,
        matchConfidence: result.similarity,
        capturedAt: capturedAt,
      );

      emit(MarkAttendanceState(status: MarkAttendanceStatus.success, similarity: result.similarity));
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

  void retry() => emit(const MarkAttendanceState(status: MarkAttendanceStatus.cameraReady));

  void _backToCamera(String message) {
    if (isClosed) return;
    emit(MarkAttendanceState(status: MarkAttendanceStatus.cameraReady, errorMessage: message));
  }

  Future<Position> _currentPosition() async {
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

    return Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, timeLimit: Duration(seconds: 15)),
    );
  }

  @override
  Future<void> close() async {
    await _camera.dispose();
    return super.close();
  }
}
