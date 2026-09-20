import 'package:flutter_bloc/flutter_bloc.dart';
import '../../services/camera_capture_controller.dart';
import '../../services/face_embedding_service.dart';
import '../../models/face_match_result.dart';
import './face_capture_state.dart';

/// Drives the capture → detect → embed flow used by the enrolment screen.
/// (The mark-attendance screen has its own cubit — it needs the same
/// capture+embed steps plus a comparison against a fetched embedding and an
/// upload afterwards, which doesn't fit this cubit's single-purpose shape.)
class FaceCaptureCubit extends Cubit<FaceCaptureState> {
  FaceCaptureCubit(this._camera, this._embeddingService) : super(const FaceCaptureState());

  final CameraCaptureController _camera;
  final FaceEmbeddingService _embeddingService;

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

  Future<void> captureAndProcess() async {
    emit(state.copyWith(status: FaceCaptureStatus.processing));
    try {
      final photo = await _camera.capture();
      final sample = await _embeddingService.generateEmbedding(photo.path);
      emit(state.copyWith(status: FaceCaptureStatus.ready, photoPath: sample.imagePath, embedding: sample.embedding));
    } on FaceProcessingException catch (e) {
      emit(state.copyWith(status: FaceCaptureStatus.cameraReady, errorMessage: e.message));
    } catch (_) {
      emit(
        state.copyWith(
          status: FaceCaptureStatus.cameraReady,
          errorMessage: 'Something went wrong capturing the photo. Try again.',
        ),
      );
    }
  }

  void retake() => emit(const FaceCaptureState(status: FaceCaptureStatus.cameraReady));

  @override
  Future<void> close() async {
    await _camera.dispose();
    return super.close();
  }
}
