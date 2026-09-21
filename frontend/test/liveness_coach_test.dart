import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/services/liveness/face_observation.dart';
import 'package:frontend/services/liveness/liveness_coach.dart';
import 'package:frontend/services/liveness/liveness_session.dart';

/// Runs a session and its coach together, one frame at a time.
class _Run {
  _Run(List<TurnSide> challenge, {LivenessConfig config = const LivenessConfig()})
    : session = LivenessSession(challenge: challenge, config: config) {
    coach = LivenessCoach(session);
  }

  final LivenessSession session;
  late final LivenessCoach coach;
  Duration t = Duration.zero;
  int _i = 0;

  LivenessGuidance frame({
    double yaw = 0,
    double ratio = 0,
    int faces = 1,
    FaceFraming framing = FaceFraming.good,
    int ms = 100,
  }) {
    t += Duration(milliseconds: ms);
    final FaceObservation o;
    if (faces == 0) {
      o = FaceObservation.noFace(at: t, frameIndex: _i++);
    } else if (faces > 1) {
      o = FaceObservation(at: t, frameIndex: _i++, faceCount: faces);
    } else {
      // A real iPhone: turning left gives a negative angle and a positive person-space nose offset.
      final deviceYaw = ratio.abs() >= 0.05 ? -ratio.sign * yaw.abs() : yaw;
      o = FaceObservation(
        at: t,
        frameIndex: _i++,
        faceCount: 1,
        trackingId: 1,
        yawDegrees: deviceYaw,
        turnRatio: ratio,
        framing: framing,
        centerX: 0.5,
        centerY: 0.45,
        widthRatio: 0.5,
      );
    }
    session.onObservation(o);
    return coach.coach(o);
  }

  LivenessGuidance settle({double yaw = 0, double ratio = 0, int frames = 6}) {
    late LivenessGuidance g;
    for (var i = 0; i < frames; i++) {
      g = frame(yaw: yaw, ratio: ratio);
    }
    return g;
  }

  /// Straight for long enough that the turns are being asked for.
  void ready() {
    for (var i = 0; i < 9; i++) {
      frame();
    }
    expect(session.phase, LivenessPhase.turning, reason: 'setup');
  }
}

void main() {
  _Run leftRight() => _Run(const [TurnSide.left, TurnSide.right]);

  group('getting ready', () {
    test('before any frame: come into the oval, with a straight zone on the line', () {
      final g = leftRight().coach.idle();

      expect(g.heading, 'Get ready');
      expect(g.prompt, 'Look at the camera, inside the oval');
      expect(g.message, 'Position your face inside the oval');
      expect(g.good, isFalse);
      expect(g.targetMin, -8);
      expect(g.targetMax, 8);
      expect(g.turnDegrees, isNull);
    });

    test('says how to fix the framing, or that nobody or two people are there', () {
      final run = leftRight();
      expect(run.frame(faces: 0).message, 'Position your face inside the oval');
      expect(run.frame(faces: 2).message, 'Only one person should be in frame');
      expect(run.frame(framing: FaceFraming.tooFar).message, 'Move a little closer');
      expect(run.frame(framing: FaceFraming.tooClose).message, 'Move back a little');
      expect(run.frame(framing: FaceFraming.offCenter).message, 'Center your face in the oval');
    });

    test('a turned head is asked to look straight', () {
      final g = leftRight().settle(yaw: 20, ratio: 0.3, frames: 3);
      expect(g.message, 'Look straight at the camera');
    });

    test('holding still: a ring that fills, and everything is right', () {
      final run = leftRight();
      run.frame();
      final early = run.frame();
      run.frame();
      run.frame();
      final later = run.frame();

      expect(later.phase, LivenessPhase.holdStill);
      expect(later.prompt, 'Hold still…');
      expect(later.good, isTrue);
      expect(later.ringProgress, greaterThan(early.ringProgress));
      expect(later.ringProgress, lessThan(1));
    });
  });

  group('the turns', () {
    test('a left turn: heading, prompt, and the green zone on the left', () {
      final run = leftRight()..ready();
      final g = run.frame();

      expect(g.heading, 'Turn 1 of 2');
      expect(g.step, 1);
      expect(g.totalSteps, 2);
      expect(g.prompt, 'Turn your head to the left');
      expect(g.targetMin, 14);
      expect(g.targetMax, 28);
    });

    test('the turn line grows toward the side being turned, and the message follows it', () {
      final run = leftRight()..ready();

      final little = run.settle(yaw: 8, ratio: 0.1);
      expect(little.turnDegrees, closeTo(8, 1));
      expect(little.message, 'Turn a little more');
      expect(little.good, isFalse);

      final enough = run.settle(yaw: 20, ratio: 0.25, frames: 1);
      expect(enough.turnDegrees, greaterThan(little.turnDegrees!));
    });

    test('a wrong-way turn is called out', () {
      final run = leftRight()..ready();
      final g = run.settle(yaw: 9, ratio: -0.12, frames: 4); // asked for left, went right, not yet far

      expect(g.message, 'Turn the other way, to your left');
      expect(g.turnDegrees, lessThan(0));
    });

    test('the next turn is to the other side, with the zone mirrored', () {
      final run = leftRight()..ready();
      run.settle(yaw: 20, ratio: 0.25, frames: 3); // first turn done
      final g = run.frame(yaw: 20, ratio: 0.25); // still turned left

      expect(g.heading, 'Turn 2 of 2');
      expect(g.step, 2);
      expect(g.prompt, 'Turn your head to the right');
      expect(g.targetMin, -28);
      expect(g.targetMax, -14);
      expect(g.message, 'Now turn to the other side');
    });

    test('the right turn first, when that is what was asked', () {
      final run = _Run(const [TurnSide.right, TurnSide.left])..ready();

      final before = run.frame();
      expect(before.prompt, 'Turn your head to the right');
      expect(before.targetMin, -28);
      expect(before.targetMax, -14);

      final turning = run.frame(yaw: 20, ratio: -0.25);
      expect(turning.turnDegrees, lessThan(-8), reason: 'the line moves to the right');
    });

    test('in the zone it says so, and the line settles on the real angle', () {
      // A long turn hold keeps the check in this turn while the reading settles.
      final run = _Run(const [
        TurnSide.right,
        TurnSide.left,
      ], config: const LivenessConfig(turnHold: Duration(seconds: 3)))..ready();
      final g = run.settle(yaw: 20, ratio: -0.25, frames: 8);

      expect(g.phase, LivenessPhase.turning);
      expect(g.turnDegrees, closeTo(-20, 1));
      expect(g.good, isTrue);
      expect(g.message, 'Good — keep going');
    });

    test('after a turn, still being on that side is not called a wrong turn; going that way again later is', () {
      final run = leftRight()..ready();
      run.settle(yaw: 20, ratio: 0.25, frames: 3); // the left turn is done
      expect(run.frame(yaw: 20, ratio: 0.25).message, 'Now turn to the other side');

      run.frame(); // back through the middle
      expect(run.frame(yaw: 9, ratio: 0.12).message, 'Turn the other way, to your right');
    });

    test('a step finishing gives a light tap, once', () {
      final run = leftRight()..ready();
      final taps = <bool>[];
      for (var i = 0; i < 4; i++) {
        taps.add(run.frame(yaw: 20, ratio: 0.25).capturing);
      }
      expect(taps.where((t) => t).length, 1);
    });

    test('losing the face mid-turn shows no turn value and says to stay in the oval', () {
      final run = leftRight()..ready();
      final g = run.frame(faces: 0);

      expect(g.turnDegrees, isNull);
      expect(g.message, 'Keep your face inside the oval');
    });
  });

  group('finishing', () {
    LivenessGuidance atLookStraight(_Run run) {
      run.ready();
      run.settle(yaw: 20, ratio: 0.25, frames: 3);
      run.frame();
      run.settle(yaw: 20, ratio: -0.25, frames: 3);
      expect(run.session.phase, LivenessPhase.lookStraight, reason: 'setup');
      return run.frame();
    }

    test('look straight: all the dots filled, and a ring that fills', () {
      final run = leftRight();
      final first = atLookStraight(run);
      final later = run.settle(frames: 3);

      expect(first.heading, 'Almost done');
      expect(first.prompt, 'Now look straight at the camera');
      expect(first.step, 2);
      expect(first.totalSteps, 2);
      expect(later.ringProgress, greaterThan(first.ringProgress));
      expect(later.good, isTrue);
      expect(later.message, 'Perfect — hold still');
    });

    test('still turned: asked to look straight', () {
      final run = leftRight();
      atLookStraight(run);
      final g = run.frame(yaw: 12, ratio: 0.14);

      expect(g.message, 'Look straight at the camera');
      expect(g.good, isFalse);
    });

    test('passed: the ring is accented and it says it is checking who it is', () {
      final run = leftRight();
      atLookStraight(run);
      final g = run.settle(frames: 8);

      expect(g.phase, LivenessPhase.passed);
      expect(g.prompt, 'Checking it is you…');
      expect(g.saved, isTrue);
      expect(g.ringProgress, 1);
    });

    test('failed: says why', () {
      final run = leftRight()..ready();
      final g = run.frame(yaw: 20, ratio: -0.25); // asked for left, went right, far enough to fail

      expect(g.phase, LivenessPhase.failed);
      expect(g.message, LivenessCoach.messageForFailure(LivenessFailure.wrongDirection));
    });
  });

  group('the failure messages', () {
    test('every failure has its own plain-words message', () {
      final messages = {for (final f in LivenessFailure.values) f: LivenessCoach.messageForFailure(f)};

      expect(messages.values.every((m) => m.isNotEmpty), isTrue);
      expect(messages.values.toSet().length, LivenessFailure.values.length, reason: 'no two failures share a message');
    });
  });
}
