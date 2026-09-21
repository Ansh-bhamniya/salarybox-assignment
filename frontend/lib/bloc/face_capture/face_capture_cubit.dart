import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../config/env.dart';
import '../../services/camera_capture_controller.dart';
import '../../services/face_embedding_service.dart';
import '../../services/liveness/enrolment_pose_guide.dart';
import '../../services/liveness/face_observation.dart';
import '../../models/face_match_result.dart';
import './face_capture_state.dart';

/// Drives the capture → detect → embed flow used by the enrolment screen, which
/// takes several photos of the same person (straight, then a little to each
/// side) so matching later copes with a small change of angle or light.
///
/// Nobody presses a shutter: the live pose is watched ([onObservation]) and each
/// photo is taken by itself once the face is in the oval and held at the pose
/// asked for. The photo actually taken is then checked again, in case the person
/// moved. (The mark-attendance screen has its own cubit — it needs the same
/// capture+embed steps plus a comparison against fetched embeddings and an
/// upload afterwards, which doesn't fit this cubit's single-purpose shape.)
class FaceCaptureCubit extends Cubit<FaceCaptureState> {
  FaceCaptureCubit(
    this._camera,
    this._embeddingService, {
    this.targetShots = Env.enrolmentShots,
    EnrolmentPoseGuide? guide,
  }) : guide = guide ?? EnrolmentPoseGuide(plan: _planFor(targetShots)),
       super(const FaceCaptureState()) {
    guidance = ValueNotifier(this.guide.idle());
  }

  final CameraCaptureController _camera;
  final FaceEmbeddingService _embeddingService;

  /// How many photos complete an enrolment.
  final int targetShots;

  /// Decides when each photo is taken.
  final EnrolmentPoseGuide guide;

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

  /// One analysed frame from the live preview. Updates the guidance and, once
  /// the pose has been held long enough, takes the photo.
  void onObservation(FaceObservation observation) {
    if (state.status != FaceCaptureStatus.cameraReady) return;

    final next = guide.onObservation(observation);
    guidance.value = next;
    if (next.shouldCapture) {
      if (!kReleaseMode) debugPrint('[enrol] auto-capture ${next.pose.name} (photo ${next.shotIndex + 1})');
      captureAndProcess();
    }
  }

  Future<void> captureAndProcess() async {
    emit(state.copyWith(status: FaceCaptureStatus.processing));
    try {
      final photo = await _camera.capture();
      final sample = await _embeddingService.generateEmbedding(photo.path, maxYawDegrees: guide.maxStillYaw);

      // The person may have moved (or left the oval) between the trigger and the shutter.
      final problem = guide.stillProblem(
        yawDegrees: sample.yawDegrees,
        centerX: sample.faceCenterX,
        centerY: sample.faceCenterY,
        widthRatio: sample.faceWidthRatio,
      );
      if (problem != null) {
        if (!kReleaseMode) {
          debugPrint(
            '[enrol] photo rejected (${guide.pose.name}): yaw ${sample.yawDegrees}, '
            'face x ${sample.faceCenterX} y ${sample.faceCenterY} w ${sample.faceWidthRatio}',
          );
        }
        throw FaceProcessingException(problem);
      }

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
