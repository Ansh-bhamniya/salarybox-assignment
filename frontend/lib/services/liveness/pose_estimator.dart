import 'dart:math';
import 'dart:ui';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import './face_observation.dart';

/// Turns ML Kit faces into [FaceObservation]s.
///
/// **Direction comes from the nose, not from the head-angle sign.** ML Kit
/// doesn't document which sign of its Euler Y angle means "left", so instead
/// the nose's offset from the middle of the eyes is used: in an upright,
/// un-mirrored front-camera frame the camera looks at the person, so the
/// person's left is the frame's right, and turning to your left moves your
/// nose toward the frame's right. That is plain geometry and doesn't depend on
/// any library convention. (Euler Y still supplies the size of the turn and a
/// second opinion.)
///
/// It is also the anti-photo cue: on a real head the nose shifts against the
/// eyes as it turns, while on a flat photo that is rotated it barely does.
class PoseEstimator {
  const PoseEstimator({this.framesMirrored = false});

  /// True if the camera hands over frames mirrored, the way a mirror would show
  /// them; the sign of the nose offset then flips. Set from what the device
  /// actually does (see the liveness debug screen).
  final bool framesMirrored;

  /// Landmarks get unreliable when the head is turned very far (the eyes nearly
  /// line up, so the eye distance collapses and the ratio explodes: a reading of
  /// -19 was seen); readings are capped so such frames stay comparable.
  static const maxRatio = 1.0;

  /// Nose offset from the middle of the eyes, in eye-distances, positive toward
  /// the frame's right. Null if the eyes coincide.
  static double? noseShift({required Point<int> leftEye, required Point<int> rightEye, required Point<int> noseBase}) {
    final eyeDistance = (leftEye.x - rightEye.x).abs();
    if (eyeDistance == 0) return null;
    final eyeMiddleX = (leftEye.x + rightEye.x) / 2;
    return (noseBase.x - eyeMiddleX) / eyeDistance;
  }

  FaceObservation observe({
    required List<Face> faces,
    required Size frameSize,
    required Duration at,
    required int frameIndex,
  }) {
    if (faces.isEmpty) return FaceObservation.noFace(at: at, frameIndex: frameIndex);
    if (faces.length > 1) return FaceObservation(at: at, frameIndex: frameIndex, faceCount: faces.length);

    final face = faces.single;
    final leftEye = face.landmarks[FaceLandmarkType.leftEye]?.position;
    final rightEye = face.landmarks[FaceLandmarkType.rightEye]?.position;
    final noseBase = face.landmarks[FaceLandmarkType.noseBase]?.position;

    final shift = (leftEye == null || rightEye == null || noseBase == null)
        ? null
        : noseShift(leftEye: leftEye, rightEye: rightEye, noseBase: noseBase);

    final box = face.boundingBox;
    return FaceObservation(
      at: at,
      frameIndex: frameIndex,
      faceCount: 1,
      trackingId: face.trackingId,
      yawDegrees: face.headEulerAngleY,
      turnRatio: shift == null ? null : (framesMirrored ? -shift : shift).clamp(-maxRatio, maxRatio).toDouble(),
      framing: FaceFraming.of(box, frameSize),
      centerX: box.center.dx / frameSize.width,
      centerY: box.center.dy / frameSize.height,
      widthRatio: box.width / frameSize.width,
    );
  }
}
