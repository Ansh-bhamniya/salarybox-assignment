import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/services/liveness/enrolment_pose_guide.dart';
import 'package:frontend/services/liveness/face_observation.dart';

/// Feeds the guide one frame at a time. Poses are in person-space: turning to
/// your left is a positive nose offset. (Only the size of the head angle is used.)
class _Feed {
  _Feed(this.guide);

  final EnrolmentPoseGuide guide;
  Duration t = Duration.zero;
  int stepMs = 100;
  int _i = 0;

  PoseGuidance frame({
    double yaw = 0,
    double ratio = 0,
    int faces = 1,
    double cx = 0.5,
    double cy = 0.45,
    double w = 0.5,
    int? ms,
  }) {
    t += Duration(milliseconds: ms ?? stepMs);
    final FaceObservation o;
    if (faces == 0) {
      o = FaceObservation.noFace(at: t, frameIndex: _i++);
    } else if (faces > 1) {
      o = FaceObservation(at: t, frameIndex: _i++, faceCount: faces);
    } else {
      // A real iPhone (mirrored frames): turning left gives a negative head angle and a
      // positive person-space nose offset, turning right the opposite. Tests give the
      // angle as a size and the nose says which way.
      final deviceYaw = ratio.abs() >= 0.05 ? -ratio.sign * yaw.abs() : yaw;
      o = FaceObservation(
        at: t,
        frameIndex: _i++,
        faceCount: 1,
        trackingId: 1,
        yawDegrees: deviceYaw,
        turnRatio: ratio,
        centerX: cx,
        centerY: cy,
        widthRatio: w,
      );
    }
    return guide.onObservation(o);
  }

  /// Holds a pose until the guide asks for the photo (or [limit] frames pass).
  PoseGuidance holdUntilCapture({double yaw = 0, double ratio = 0, int limit = 40}) {
    late PoseGuidance g;
    for (var i = 0; i < limit; i++) {
      g = frame(yaw: yaw, ratio: ratio);
      if (g.shouldCapture) return g;
    }
    return g;
  }

  /// Holds one reading for a while so the smoothed turn line has settled on it.
  PoseGuidance settle({double yaw = 0, double ratio = 0, int frames = 8}) {
    late PoseGuidance g;
    for (var i = 0; i < frames; i++) {
      g = frame(yaw: yaw, ratio: ratio);
    }
    return g;
  }

  /// Frames of a neutral face until the "photo saved" pause is over.
  void pastSavedPause({double yaw = 0, double ratio = 0}) {
    for (var i = 0; i < 40 && frame(yaw: yaw, ratio: ratio).advice == PoseAdvice.saved; i++) {}
  }

  /// Takes the straight photo, which fixes the baseline.
  void acceptStraight({double yaw = 0, double ratio = 0}) {
    final g = holdUntilCapture(yaw: yaw, ratio: ratio);
    expect(g.shouldCapture, isTrue, reason: 'setup: the straight photo should have been requested');
    guide.shotAccepted();
  }
}

void main() {
  EnrolmentPoseGuide guide() => EnrolmentPoseGuide();

  group('straight photo', () {
    test('is requested once the face has been held straight and steady long enough', () {
      final feed = _Feed(guide());

      final progress = <double>[];
      PoseGuidance? capture;
      for (var i = 0; i < 30 && capture == null; i++) {
        final g = feed.frame();
        progress.add(g.holdProgress);
        if (g.shouldCapture) capture = g;
      }

      expect(capture, isNotNull);
      expect(capture!.advice, PoseAdvice.holdStill);
      expect(capture.holdProgress, 1);
      expect(progress.first, lessThan(0.2));
      expect(progress, orderedEquals([...progress]..sort()), reason: 'progress only grows');
      expect(progress.length, greaterThan(12), reason: 'about 1.5 s of holding, not a moment');
    });

    test('asks for it only once, then waits for the result', () {
      final feed = _Feed(guide());
      expect(feed.holdUntilCapture().shouldCapture, isTrue);

      for (var i = 0; i < 10; i++) {
        final g = feed.frame();
        expect(g.shouldCapture, isFalse);
        expect(g.holdProgress, 1);
      }
    });

    test('is not requested while the head is turned or the nose is off', () {
      final feed = _Feed(guide());
      for (var i = 0; i < 15; i++) {
        final g = feed.frame(yaw: 15, ratio: 0.3);
        expect(g.shouldCapture, isFalse);
        expect(g.advice, PoseAdvice.lookStraight);
        expect(g.message, 'Look straight at the camera');
      }
      final onlyNose = feed.frame(yaw: 2, ratio: 0.22);
      expect(onlyNose.advice, PoseAdvice.lookStraight);
    });

    test('says how to fix the framing', () {
      final feed = _Feed(guide());
      expect(feed.frame(w: 0.2).advice, PoseAdvice.moveCloser);
      expect(feed.frame(w: 0.85).advice, PoseAdvice.moveBack);
      expect(feed.frame(cx: 0.9).advice, PoseAdvice.centerFace);
      expect(feed.frame(cy: 0.85).advice, PoseAdvice.centerFace);
      expect(feed.frame().advice, PoseAdvice.holdStill);
    });

    test('nobody in view, or two people', () {
      final feed = _Feed(guide());
      expect(feed.frame(faces: 0).advice, PoseAdvice.noFace);
      expect(feed.frame(faces: 2).advice, PoseAdvice.multipleFaces);
    });

    test('one noisy frame does not restart the hold, a real break does', () {
      final feed = _Feed(guide());
      for (var i = 0; i < 4; i++) {
        feed.frame();
      }
      feed.frame(yaw: 20, ratio: 0.3); // a glitch
      var capture = false;
      for (var i = 0; i < 25 && !capture; i++) {
        capture = feed.frame().shouldCapture;
      }
      expect(capture, isTrue, reason: 'the hold survived a single bad frame');

      final feed2 = _Feed(guide());
      for (var i = 0; i < 4; i++) {
        feed2.frame();
      }
      for (var i = 0; i < 4; i++) {
        feed2.frame(faces: 0); // 400 ms gone: longer than the grace
      }
      expect(feed2.frame().holdProgress, lessThan(0.3), reason: 'started again from nothing');
    });

    test('a head that keeps wandering never counts as still', () {
      final feed = _Feed(guide());
      var captured = false;
      for (var i = 0; i < 40; i++) {
        final g = feed.frame(yaw: i.isEven ? -6 : 6); // 12° swing, more than the 5° allowed
        captured = captured || g.shouldCapture;
      }
      expect(captured, isFalse);
    });
  });

  group('turn photos', () {
    _Feed afterStraight({double baseYaw = 0, double baseRatio = 0}) {
      final feed = _Feed(guide());
      feed.acceptStraight(yaw: baseYaw, ratio: baseRatio);
      expect(feed.guide.pose, EnrolmentPose.left);
      feed.pastSavedPause();
      return feed;
    }

    test('the second photo is a turn to the left, with a target range on the left', () {
      final feed = afterStraight();
      final g = feed.frame();
      expect(g.pose, EnrolmentPose.left);
      expect(g.prompt, 'Turn your head to the left');
      expect(g.targetMin, 14);
      expect(g.targetMax, 26);
      expect(g.shotIndex, 1);
      expect(g.totalShots, 3);
    });

    test('not turned enough yet: keep turning', () {
      final feed = afterStraight();
      final g = feed.settle(yaw: 8, ratio: 0.1);
      expect(g.advice, PoseAdvice.turnMore);
      expect(g.message, 'Turn a little more');
      expect(g.turnDegrees, closeTo(8, 0.5));
    });

    test('the head is turned enough but the nose has not moved: not a real turn yet', () {
      final feed = afterStraight();
      final g = feed.frame(yaw: 20, ratio: 0.06);
      expect(g.advice, PoseAdvice.turnMore);
    });

    test('turned the wrong way', () {
      final feed = afterStraight();
      final g = feed.settle(yaw: 18, ratio: -0.25); // asked for left, went right
      expect(g.advice, PoseAdvice.wrongWay);
      expect(g.message, 'Turn the other way, to your left');
      expect(g.turnDegrees, closeTo(-18, 1));
    });

    test('turned too far', () {
      final feed = afterStraight();
      expect(feed.frame(yaw: 32, ratio: 0.4).advice, PoseAdvice.turnBack);
      expect(
        feed.frame(yaw: 62, ratio: -1.0).advice,
        PoseAdvice.turnBack,
        reason: 'far past sensible: no "wrong way" from an exploded reading',
      );
    });

    test('in the target range for long enough: the photo is requested', () {
      final feed = afterStraight();
      PoseGuidance? capture;
      final progress = <double>[];
      for (var i = 0; i < 30 && capture == null; i++) {
        final g = feed.frame(yaw: 20, ratio: 0.25);
        progress.add(g.holdProgress);
        if (g.shouldCapture) capture = g;
      }
      expect(capture, isNotNull);
      expect(capture!.turnDegrees, closeTo(20, 1), reason: 'the line has settled on the real angle by then');
      expect(capture.inPosition, isTrue);
      expect(progress.first, lessThan(1));
    });

    test('the turn to the right has a mirrored target and negative degrees', () {
      final feed = afterStraight();
      feed.holdUntilCapture(yaw: 20, ratio: 0.25);
      feed.guide.shotAccepted();
      expect(feed.guide.pose, EnrolmentPose.right);
      feed.pastSavedPause(yaw: 20, ratio: 0.25);

      final g = feed.settle(yaw: 18, ratio: -0.25, frames: 6);
      expect(g.prompt, 'Turn your head to the right');
      expect(g.targetMin, -26);
      expect(g.targetMax, -14);
      expect(g.turnDegrees, closeTo(-18, 1));

      final capture = feed.holdUntilCapture(yaw: 20, ratio: -0.25);
      expect(capture.shouldCapture, isTrue);
    });

    test('turn is measured from the person\'s own straight-ahead baseline', () {
      // This person looks straight with the nose at +0.06 and the head 3° round.
      final feed = afterStraight(baseYaw: 3, baseRatio: 0.06);
      expect(feed.guide.baselineRatio, closeTo(0.06, 1e-9));
      expect(
        feed.guide.baselineYaw,
        closeTo(-3, 1e-9),
        reason: 'the angle runs negative toward the left on this convention',
      );

      // Raw yaw 17 / nose 0.31 is only 14° / 0.25 from their baseline: a real turn.
      final g = feed.settle(yaw: 17, ratio: 0.31, frames: 6);
      expect(g.turnDegrees, closeTo(14, 1.5));
      expect(g.advice, PoseAdvice.holdStill);

      // A raw 10° / 0.2 is only 7° / 0.14 from this person's straight: not turned enough.
      final other = afterStraight(baseYaw: 3, baseRatio: 0.06);
      expect(other.frame(yaw: 10, ratio: 0.2).advice, PoseAdvice.turnMore);
    });

    test('turned photos allow a little more room in the frame than straight ones', () {
      final feed = afterStraight();
      // Off by 0.2 in x: too far for a straight photo (0.15), fine for a turned one (0.22).
      expect(feed.frame(yaw: 20, ratio: 0.25, cx: 0.7).advice, PoseAdvice.holdStill);
      expect(feed.frame(yaw: 20, ratio: 0.25, cx: 0.8).advice, PoseAdvice.centerFace);
    });
  });

  group('after the photo is taken', () {
    test('a rejected photo asks for the same pose again, and does not fix the baseline', () {
      final feed = _Feed(guide());
      expect(feed.holdUntilCapture(yaw: 2, ratio: 0.08).shouldCapture, isTrue);

      feed.guide.shotRejected();

      expect(feed.guide.pose, EnrolmentPose.straight);
      expect(feed.guide.baselineRatio, 0);
      expect(feed.frame().holdProgress, lessThan(0.3), reason: 'the hold starts over');
      expect(feed.holdUntilCapture().shouldCapture, isTrue, reason: 'and can be taken again');
    });

    test('three accepted photos complete the enrolment', () {
      final feed = _Feed(guide());
      feed.acceptStraight();
      feed.pastSavedPause();
      feed.holdUntilCapture(yaw: 20, ratio: 0.25);
      feed.guide.shotAccepted();
      feed.pastSavedPause(yaw: 20, ratio: -0.25);
      feed.holdUntilCapture(yaw: 20, ratio: -0.25);
      feed.guide.shotAccepted();

      expect(feed.guide.isComplete, isTrue);
      expect(feed.frame().shouldCapture, isFalse);
    });

    test('reset starts over from the first pose with no baseline', () {
      final feed = _Feed(guide());
      feed.acceptStraight(yaw: 3, ratio: 0.06);
      feed.guide.reset();

      expect(feed.guide.shotIndex, 0);
      expect(feed.guide.pose, EnrolmentPose.straight);
      expect(feed.guide.baselineRatio, 0);
    });
  });

  group('checking the photo that was actually taken', () {
    test('a straight photo must be close to straight', () {
      final g = guide();
      expect(g.isStillAcceptable(3), isTrue);
      expect(g.isStillAcceptable(-11), isTrue);
      expect(g.isStillAcceptable(20), isFalse);
    });

    test('a turn photo must show a real turn, whichever sign the photo uses', () {
      final feed = _Feed(guide());
      feed.acceptStraight();

      expect(feed.guide.isStillAcceptable(19), isTrue);
      expect(feed.guide.isStillAcceptable(-19), isTrue);
      expect(feed.guide.isStillAcceptable(4), isFalse, reason: 'moved back to straight before the shutter');
      expect(feed.guide.isStillAcceptable(45), isFalse, reason: 'turned too far');
    });

    test('an unknown angle is accepted rather than blocking the enrolment', () {
      expect(guide().isStillAcceptable(null), isTrue);
    });

    test('how far the photo may turn before being refused depends on the pose', () {
      final feed = _Feed(guide());
      expect(feed.guide.maxStillYaw, 25);
      feed.acceptStraight();
      expect(feed.guide.maxStillYaw, greaterThan(34));
    });
  });

  group('unhurried, and steady', () {
    test('the straight photo needs about a second and a half of holding still', () {
      final feed = _Feed(guide());
      var frames = 0;
      while (!feed.frame().shouldCapture && frames < 60) {
        frames++;
      }
      expect(frames * 100, greaterThanOrEqualTo(1400));
      expect(frames * 100, lessThan(1700));
    });

    test('a turn photo is held as long as the first one, not faster', () {
      final feed = _Feed(guide());
      feed.acceptStraight();
      feed.pastSavedPause();
      var frames = 0;
      while (!feed.frame(yaw: 20, ratio: 0.25).shouldCapture && frames < 60) {
        frames++;
      }
      expect(frames * 100, greaterThanOrEqualTo(1400));
      expect(frames * 100, lessThan(1700));
    });

    test('a face box that keeps drifting across the frame is not still', () {
      final feed = _Feed(guide());
      var captured = false;
      for (var i = 0; i < 60; i++) {
        final g = feed.frame(cx: 0.42 + (i % 8) * 0.02); // sliding 0.14 sideways and back
        captured = captured || g.shouldCapture;
      }
      expect(captured, isFalse);
    });

    test('after a photo is kept there is a short "saved" pause before the next pose is asked for', () {
      final feed = _Feed(guide());
      feed.holdUntilCapture();
      feed.guide.shotAccepted();

      final during = <PoseAdvice>[];
      for (var i = 0; i < 10; i++) {
        during.add(feed.frame(yaw: 20, ratio: 0.25).advice);
      }
      expect(during, everyElement(PoseAdvice.saved), reason: 'no new hold while the pause lasts (about a second)');
      expect(feed.frame(yaw: 20, ratio: 0.25).advice, isNot(PoseAdvice.saved), reason: 'the pause is over');
      for (var i = 0; i < 8; i++) {
        feed.frame(yaw: 20, ratio: 0.25);
      }
      expect(feed.frame(yaw: 20, ratio: 0.25).advice, PoseAdvice.holdStill);
    });

    test('the pause never captures, even with the head already in the next zone', () {
      final feed = _Feed(guide());
      feed.holdUntilCapture();
      feed.guide.shotAccepted();
      for (var i = 0; i < 9; i++) {
        expect(feed.frame(yaw: 20, ratio: 0.25).shouldCapture, isFalse);
      }
    });
  });

  group('the ring is split into one piece per photo', () {
    test('three pieces, none done at the start, and the hold fills only the current piece', () {
      final feed = _Feed(guide());
      final g = feed.frame();
      expect(g.ringSegments, 3);
      expect(g.ringDone, 0);

      final mid = feed.settle();
      expect(mid.ringDone, 0);
      expect(mid.ringProgress, greaterThan(0));
      expect(mid.ringProgress, lessThan(1));
    });

    test('a kept photo leaves its piece filled while the next one starts empty', () {
      final feed = _Feed(guide());
      feed.acceptStraight();
      final saved = feed.frame();
      expect(saved.ringDone, 1);
      expect(saved.ringProgress, 0);

      feed.pastSavedPause();
      final turning = feed.frame(yaw: 20, ratio: 0.25);
      expect(turning.ringSegments, 3);
      expect(turning.ringDone, 1);
    });

    test('a rejected photo does not fill its piece', () {
      final feed = _Feed(guide());
      feed.holdUntilCapture();
      feed.guide.shotRejected();
      expect(feed.frame().ringDone, 0);
    });

    test('all pieces are done once every photo is kept', () {
      final feed = _Feed(guide());
      feed.acceptStraight();
      feed.pastSavedPause();
      feed.holdUntilCapture(yaw: 20, ratio: 0.25);
      feed.guide.shotAccepted();
      feed.pastSavedPause();
      feed.holdUntilCapture(yaw: -20, ratio: -0.25);
      feed.guide.shotAccepted();

      expect(feed.frame(yaw: -20, ratio: -0.25).ringDone, 3);
    });
  });

  group('the turn line reading', () {
    // Measured on an iPhone with mirrored frames: turning to your left makes the
    // head angle more negative while the (person-space) nose offset goes positive.
    test('is steady around straight: the sign does not flip with the nose noise', () {
      final feed = _Feed(guide());
      final readings = <double>[];
      for (var i = 0; i < 12; i++) {
        // Nose offset wobbling either side of zero, head angle a steady -2 degrees.
        final g = feed.frame(yaw: -2, ratio: i.isEven ? 0.03 : -0.03);
        readings.add(g.turnDegrees!);
      }
      expect(
        readings.every((r) => r > 0),
        isTrue,
        reason: 'all on the same side (-2 degrees on this phone means a hair to the left)',
      );
      expect(readings.every((r) => r < 4), isTrue);
    });

    test('a turn to the left reads positive and a turn to the right negative, growing with the angle', () {
      final feed = _Feed(guide());
      feed.frame(yaw: -20, ratio: 0.25); // learns which way the angle runs
      double read(double yaw, double ratio) {
        var g = feed.frame(yaw: yaw, ratio: ratio);
        for (var i = 0; i < 12; i++) {
          g = feed.frame(yaw: yaw, ratio: ratio);
        }
        return g.turnDegrees!;
      }

      final left10 = read(-10, 0.15);
      final left20 = read(-20, 0.25);
      final right20 = read(20, -0.25);

      expect(left10, greaterThan(0));
      expect(left20, greaterThan(left10));
      expect(right20, lessThan(0));
      expect(left20, closeTo(20, 1.5));
    });

    test('learns the other convention too, for a device whose angle runs the other way', () {
      final feed = _Feed(guide());
      // Here turning left gives a positive angle AND a positive nose offset.
      for (var i = 0; i < 15; i++) {
        feed.frame(yaw: 20, ratio: 0.25);
      }
      final g = feed.frame(yaw: 20, ratio: 0.25);
      expect(g.turnDegrees, closeTo(20, 1.5), reason: 'still reads as 20 degrees to the left');
    });

    test('moves smoothly instead of jumping to each new reading', () {
      final feed = _Feed(guide());
      for (var i = 0; i < 10; i++) {
        feed.frame(yaw: 0, ratio: 0);
      }
      final first = feed.frame(yaw: -20, ratio: 0.25).turnDegrees!;
      expect(first, greaterThan(5));
      expect(first, lessThan(20), reason: 'a fraction of the way on the first frame');
    });
  });

  group('checking the photo that was actually taken (framing)', () {
    test('a photo with the face well inside the frame is fine', () {
      expect(guide().stillProblem(yawDegrees: 2, centerX: 0.5, centerY: 0.45, widthRatio: 0.5), isNull);
    });

    test('a face off to a side, or too small, or too big is refused, with a clear reason', () {
      final g = guide();
      for (final args in [(0.9, 0.45, 0.5), (0.5, 0.95, 0.5), (0.5, 0.45, 0.12), (0.5, 0.45, 0.95)]) {
        expect(
          g.stillProblem(yawDegrees: 2, centerX: args.$1, centerY: args.$2, widthRatio: args.$3),
          contains('inside the oval'),
          reason: '$args',
        );
      }
    });

    test('a moved head is reported as moving, whatever the framing', () {
      expect(guide().stillProblem(yawDegrees: 25, centerX: 0.5, centerY: 0.45, widthRatio: 0.5), contains('moved'));
    });

    test('a photo with no framing information is judged on the head angle alone', () {
      expect(guide().stillProblem(yawDegrees: 2), isNull);
      expect(guide().stillProblem(), isNull);
    });
  });
}
