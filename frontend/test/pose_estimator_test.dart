import 'dart:math';
import 'dart:ui';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/services/camera_input_image.dart';
import 'package:frontend/services/liveness/face_observation.dart';
import 'package:frontend/services/liveness/pose_estimator.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';

Face _face({
  required Point<int> leftEye,
  required Point<int> rightEye,
  required Point<int> nose,
  double? yaw = 0,
  int? trackingId = 7,
  Rect box = const Rect.fromLTWH(200, 240, 400, 500),
  bool withLandmarks = true,
}) {
  return Face(
    boundingBox: box,
    landmarks: withLandmarks
        ? {
            FaceLandmarkType.leftEye: FaceLandmark(type: FaceLandmarkType.leftEye, position: leftEye),
            FaceLandmarkType.rightEye: FaceLandmark(type: FaceLandmarkType.rightEye, position: rightEye),
            FaceLandmarkType.noseBase: FaceLandmark(type: FaceLandmarkType.noseBase, position: nose),
          }
        : {},
    contours: {},
    headEulerAngleY: yaw,
    trackingId: trackingId,
  );
}

void main() {
  const frame = Size(800, 1000);

  group('PoseEstimator.noseShift', () {
    test('a nose midway between the eyes is zero', () {
      expect(
        PoseEstimator.noseShift(
          leftEye: const Point(300, 400),
          rightEye: const Point(500, 400),
          noseBase: const Point(400, 520),
        ),
        0,
      );
    });

    test('is measured in eye-distances, positive toward the frame right', () {
      // Eyes 200px apart, middle at x=400; nose 40px to the right of it.
      expect(
        PoseEstimator.noseShift(
          leftEye: const Point(300, 400),
          rightEye: const Point(500, 400),
          noseBase: const Point(440, 520),
        ),
        closeTo(0.2, 1e-9),
      );
      expect(
        PoseEstimator.noseShift(
          leftEye: const Point(300, 400),
          rightEye: const Point(500, 400),
          noseBase: const Point(360, 520),
        ),
        closeTo(-0.2, 1e-9),
      );
    });

    test('does not depend on which eye ML Kit calls left', () {
      final a = PoseEstimator.noseShift(
        leftEye: const Point(300, 400),
        rightEye: const Point(500, 400),
        noseBase: const Point(440, 520),
      );
      final b = PoseEstimator.noseShift(
        leftEye: const Point(500, 400),
        rightEye: const Point(300, 400),
        noseBase: const Point(440, 520),
      );
      expect(a, b);
    });

    test('is scale free: the same face twice as big gives the same number', () {
      final small = PoseEstimator.noseShift(
        leftEye: const Point(300, 400),
        rightEye: const Point(500, 400),
        noseBase: const Point(440, 520),
      );
      final big = PoseEstimator.noseShift(
        leftEye: const Point(600, 800),
        rightEye: const Point(1000, 800),
        noseBase: const Point(880, 1040),
      );
      expect(big, closeTo(small!, 1e-9));
    });

    test('eyes at the same x cannot be measured', () {
      expect(
        PoseEstimator.noseShift(
          leftEye: const Point(400, 400),
          rightEye: const Point(400, 410),
          noseBase: const Point(400, 520),
        ),
        isNull,
      );
    });
  });

  group('PoseEstimator.observe', () {
    Face turned({required int noseX, double yaw = 20}) =>
        _face(leftEye: const Point(300, 400), rightEye: const Point(500, 400), nose: Point(noseX, 520), yaw: yaw);

    test('no face → an empty observation', () {
      final o = const PoseEstimator().observe(
        faces: [],
        frameSize: frame,
        at: const Duration(seconds: 1),
        frameIndex: 3,
      );
      expect(o.faceCount, 0);
      expect(o.usable, isFalse);
      expect(o.frameIndex, 3);
    });

    test('two faces → counted but not usable', () {
      final f = turned(noseX: 400);
      final o = const PoseEstimator().observe(faces: [f, f], frameSize: frame, at: Duration.zero, frameIndex: 0);
      expect(o.faceCount, 2);
      expect(o.usable, isFalse);
    });

    test('a nose toward the frame right is the person turning to their own left (frames not mirrored)', () {
      final o = const PoseEstimator().observe(
        faces: [turned(noseX: 440)],
        frameSize: frame,
        at: Duration.zero,
        frameIndex: 0,
      );
      expect(o.turnRatio, closeTo(0.2, 1e-9));
      expect(o.side, TurnSide.left);
    });

    test('a nose toward the frame left is the person turning to their own right', () {
      final o = const PoseEstimator().observe(
        faces: [turned(noseX: 360)],
        frameSize: frame,
        at: Duration.zero,
        frameIndex: 0,
      );
      expect(o.turnRatio, closeTo(-0.2, 1e-9));
      expect(o.side, TurnSide.right);
    });

    test('mirrored frames flip the direction', () {
      final o = const PoseEstimator(
        framesMirrored: true,
      ).observe(faces: [turned(noseX: 440)], frameSize: frame, at: Duration.zero, frameIndex: 0);
      expect(o.turnRatio, closeTo(-0.2, 1e-9));
      expect(o.side, TurnSide.right);
    });

    test('carries yaw, tracking id and framing through', () {
      final o = const PoseEstimator().observe(
        faces: [turned(noseX: 400, yaw: -13.5)],
        frameSize: frame,
        at: Duration.zero,
        frameIndex: 0,
      );
      expect(o.yawDegrees, -13.5);
      expect(o.trackingId, 7);
      expect(o.framing, FaceFraming.good);
      expect(o.usable, isTrue);
    });

    test('missing landmarks or yaw make the face unusable rather than throwing', () {
      final noLandmarks = _face(
        leftEye: const Point(0, 0),
        rightEye: const Point(0, 0),
        nose: const Point(0, 0),
        withLandmarks: false,
      );
      expect(
        const PoseEstimator().observe(faces: [noLandmarks], frameSize: frame, at: Duration.zero, frameIndex: 0).usable,
        isFalse,
      );

      final noYaw = _face(
        leftEye: const Point(300, 400),
        rightEye: const Point(500, 400),
        nose: const Point(400, 520),
        yaw: null,
      );
      expect(
        const PoseEstimator().observe(faces: [noYaw], frameSize: frame, at: Duration.zero, frameIndex: 0).usable,
        isFalse,
      );
    });
  });

  group('PoseEstimator readings at the extremes', () {
    test('an exploding nose offset (eyes nearly lined up at a far turn) is capped', () {
      // Seen on a device: yaw -75 read a nose offset of -19.
      final f = _face(
        leftEye: const Point(400, 400),
        rightEye: const Point(401, 400),
        nose: const Point(420, 520),
        yaw: -75,
      );
      final o = const PoseEstimator().observe(faces: [f], frameSize: frame, at: Duration.zero, frameIndex: 0);
      expect(o.turnRatio, PoseEstimator.maxRatio);
      final o2 = const PoseEstimator().observe(
        faces: [_face(leftEye: const Point(400, 400), rightEye: const Point(401, 400), nose: const Point(380, 520))],
        frameSize: frame,
        at: Duration.zero,
        frameIndex: 0,
      );
      expect(o2.turnRatio, -PoseEstimator.maxRatio);
    });

    test('reports where the face sits in the frame, so framing can be explained', () {
      final f = _face(leftEye: const Point(300, 400), rightEye: const Point(500, 400), nose: const Point(400, 520));
      final o = const PoseEstimator().observe(faces: [f], frameSize: frame, at: Duration.zero, frameIndex: 0);
      expect(o.centerX, closeTo(0.5, 1e-9)); // box 200..600 in an 800 wide frame
      expect(o.centerY, closeTo(0.49, 1e-9)); // box 240..740 in a 1000 tall frame
      expect(o.widthRatio, closeTo(0.5, 1e-9));
    });
  });

  group('FaceFraming', () {
    test('a centred, mid-size face is good', () {
      expect(FaceFraming.of(const Rect.fromLTWH(200, 240, 400, 500), frame), FaceFraming.good);
    });

    test('too small, too big and off centre', () {
      expect(FaceFraming.of(const Rect.fromLTWH(350, 400, 100, 130), frame), FaceFraming.tooFar);
      expect(FaceFraming.of(const Rect.fromLTWH(50, 100, 700, 800), frame), FaceFraming.tooClose);
      expect(FaceFraming.of(const Rect.fromLTWH(0, 240, 400, 500), frame), FaceFraming.offCenter);
    });
  });

  test('TurnSide.opposite', () {
    expect(TurnSide.left.opposite, TurnSide.right);
    expect(TurnSide.right.opposite, TurnSide.left);
  });

  group('a face on the iPhone frame', () {
    test('the iPhone face that read as x 0.28 y 0.90 is centred once the size is right', () {
      // Box centre in pixels of the upright 720x1280 frame.
      const box = Rect.fromLTWH(130, 420, 460, 480); // centre (360, 660)
      final wrong = FaceFraming.of(box, const Size(1280, 720)); // the old, swapped size
      final right = FaceFraming.of(
        box,
        uprightSizeOf(width: 720, height: 1280, sensorOrientation: 270, streamIsUpright: true),
      );

      expect(wrong, isNot(FaceFraming.good));
      expect(right, FaceFraming.good);
    });
  });
}
