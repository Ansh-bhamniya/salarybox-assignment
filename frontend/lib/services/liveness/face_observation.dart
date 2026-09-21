import 'dart:ui';

/// A side of the person's own body: "left" is their left hand, not the screen's.
enum TurnSide {
  left,
  right;

  TurnSide get opposite => this == left ? right : left;
}

/// How well the face sits in the framing oval.
enum FaceFraming {
  good,
  tooFar,
  tooClose,
  offCenter;

  /// How well the face sits in the framing oval: not too small or big, near the middle.
  static FaceFraming of(Rect box, Size frame) {
    final widthRatio = box.width / frame.width;
    final centerX = box.center.dx / frame.width;
    final centerY = box.center.dy / frame.height;

    if (widthRatio < 0.30) return tooFar;
    if (widthRatio > 0.70) return tooClose;
    if ((centerX - 0.5).abs() > 0.15 || (centerY - 0.45).abs() > 0.18) return offCenter;
    return good;
  }
}

/// What one analysed camera frame says about the person in front of the camera.
class FaceObservation {
  const FaceObservation({
    required this.at,
    required this.frameIndex,
    required this.faceCount,
    this.trackingId,
    this.yawDegrees,
    this.turnRatio,
    this.framing,
    this.centerX,
    this.centerY,
    this.widthRatio,
  });

  /// A frame with nobody in it.
  const FaceObservation.noFace({required this.at, required this.frameIndex})
    : faceCount = 0,
      trackingId = null,
      yawDegrees = null,
      turnRatio = null,
      framing = null,
      centerX = null,
      centerY = null,
      widthRatio = null;

  /// Time since the analysis started (a monotonic clock).
  final Duration at;

  /// Which analysed frame this is, so the frame itself can be looked up later.
  final int frameIndex;

  final int faceCount;

  /// ML Kit's id for the face; stays the same while the same face stays in view.
  final int? trackingId;

  /// ML Kit's head rotation about the vertical axis, in degrees. Only its size
  /// is trusted: which sign means left is not documented.
  final double? yawDegrees;

  /// How far the nose has moved off the middle of the eyes, in eye-distances,
  /// signed so that **positive means turned toward the person's left**. See
  /// `PoseEstimator` for why this, not [yawDegrees], gives the direction.
  final double? turnRatio;

  final FaceFraming? framing;

  /// Where the face box sits in the (upright) frame, 0..1 from the left / top,
  /// and how wide it is relative to the frame. What [framing] is worked out from.
  final double? centerX;
  final double? centerY;
  final double? widthRatio;

  /// Exactly one face, with both pose signals available.
  bool get usable => faceCount == 1 && yawDegrees != null && turnRatio != null;

  /// The side the person is turned toward, or null if [turnRatio] is missing.
  TurnSide? get side => turnRatio == null ? null : (turnRatio! > 0 ? TurnSide.left : TurnSide.right);
}
