import 'dart:math';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/services/liveness/face_observation.dart';
import 'package:frontend/services/liveness/liveness_session.dart';

/// Feeds a session one 100 ms frame at a time. Poses are in person-space:
/// turning left is a positive nose offset and (here) a positive head angle.
class _Sim {
  _Sim(this.session);

  final LivenessSession session;

  /// This person's own "looking straight" readings, added to every frame.
  double baseYaw = 0;
  double baseRatio = 0;

  /// Time between frames; real analysis runs at about 28 fps (35 ms).
  int stepMs = 100;
  Duration t = Duration.zero;
  int _index = 0;
  final keeps = <KeepFrame>[];

  KeepFrame? frame({
    double yaw = 0,
    double ratio = 0,
    int faces = 1,
    int? id = 1,
    FaceFraming framing = FaceFraming.good,
    int? ms,
    double cx = 0.5,
    double cy = 0.5,
  }) {
    t += Duration(milliseconds: ms ?? stepMs);
    final FaceObservation o;
    if (faces == 0) {
      o = FaceObservation.noFace(at: t, frameIndex: _index++);
    } else if (faces > 1) {
      o = FaceObservation(at: t, frameIndex: _index++, faceCount: faces);
    } else {
      o = FaceObservation(
        at: t,
        frameIndex: _index++,
        faceCount: 1,
        trackingId: id,
        yawDegrees: yaw + baseYaw,
        turnRatio: ratio + baseRatio,
        framing: framing,
        centerX: cx,
        centerY: cy,
      );
    }
    final keep = session.onObservation(o);
    if (keep != null) keeps.add(keep);
    return keep;
  }

  void neutral(Duration d, {int? id = 1}) {
    final end = t + d;
    while (t < end) {
      frame(id: id);
    }
  }

  /// Head turned toward [side], [frames] frames in a row.
  void turn(TurnSide side, {int frames = 2, double yaw = 20, double ratio = 0.25, int? id = 1}) {
    final sign = side == TurnSide.left ? 1 : -1;
    for (var i = 0; i < frames; i++) {
      frame(yaw: sign * yaw, ratio: sign * ratio, id: id);
    }
  }

  void gap(Duration d) => t += d;
}

const _ms = Duration(milliseconds: 1);
Duration ms(int n) => _ms * n;

/// A session already through "hold still", now asking for the first turn.
_Sim _started({List<TurnSide> challenge = const [TurnSide.left, TurnSide.right], LivenessConfig? config}) {
  final sim = _Sim(LivenessSession(challenge: challenge, config: config ?? const LivenessConfig()));
  sim.neutral(ms(800));
  expect(sim.session.phase, LivenessPhase.turning, reason: 'setup: hold still should have completed');
  return sim;
}

void main() {
  test('the attendance screen holds still as long as an enrolment photo, before and after the turns', () {
    expect(LivenessConfig.attendance.holdStillFor, const Duration(milliseconds: 1500));
    expect(LivenessConfig.attendance.finalHoldFor, const Duration(milliseconds: 1500));
    expect(LivenessConfig.attendance.holdStillFor, greaterThan(const LivenessConfig().holdStillFor));
    // Everything else is the same as the defaults.
    expect(LivenessConfig.attendance.turnYawDegrees, const LivenessConfig().turnYawDegrees);
    expect(LivenessConfig.attendance.sessionTimeout, greaterThan(LivenessConfig.attendance.holdStillFor * 4));
  });

  group('happy path', () {
    test('left then right passes, and asks for the right frames to be kept', () {
      final sim = _Sim(LivenessSession(challenge: const [TurnSide.left, TurnSide.right]));

      sim.neutral(ms(800));
      expect(sim.session.phase, LivenessPhase.turning);
      expect(sim.session.target, TurnSide.left);

      sim.turn(TurnSide.left);
      expect(sim.session.turnsCompleted, 1);
      expect(sim.session.target, TurnSide.right);

      sim.frame(); // through the middle
      sim.turn(TurnSide.right);
      expect(sim.session.phase, LivenessPhase.lookStraight);
      expect(sim.session.target, isNull);

      sim.neutral(ms(600));
      expect(sim.session.phase, LivenessPhase.passed);
      expect(sim.session.failure, isNull);

      expect(sim.keeps.map((k) => k.role), [
        FrameRole.start,
        FrameRole.turnPeak,
        FrameRole.turnPeak,
        FrameRole.finalStraight,
      ]);
      expect(sim.keeps.where((k) => k.role == FrameRole.turnPeak).map((k) => k.turnIndex), [0, 1]);
    });

    test('right then left passes too', () {
      final sim = _started(challenge: const [TurnSide.right, TurnSide.left]);

      expect(sim.session.target, TurnSide.right);
      sim.turn(TurnSide.right);
      sim.frame();
      sim.turn(TurnSide.left);
      sim.neutral(ms(600));

      expect(sim.session.phase, LivenessPhase.passed);
    });

    test('the result records the challenge, how long it took and the peaks', () {
      final sim = _started();
      sim.turn(TurnSide.left, yaw: 21, ratio: 0.26);
      sim.frame();
      sim.turn(TurnSide.right, yaw: 19, ratio: 0.22);
      sim.neutral(ms(600));

      final result = sim.session.result!;
      expect(result.challenge, [TurnSide.left, TurnSide.right]);
      expect(result.peakYaws, [21, -19]);
      expect(result.peakTurnRatios, [0.26, -0.22]);
      expect(result.duration, greaterThan(ms(1500)));
    });

    test('being still on the first side while the second turn is asked for is not a mistake', () {
      final sim = _started();
      sim.turn(TurnSide.left);
      // Head still turned left when "now turn right" appears: neither a fail nor progress.
      sim.turn(TurnSide.left, frames: 4);
      expect(sim.session.phase, LivenessPhase.turning);
      expect(sim.session.failure, isNull);

      sim.frame();
      sim.turn(TurnSide.right);
      expect(sim.session.phase, LivenessPhase.lookStraight);
    });

    test('a random challenge is always one side then the other, in either order', () {
      final random = Random(42);
      final firsts = <TurnSide>{};
      for (var i = 0; i < 200; i++) {
        final challenge = LivenessSession.random(random).challenge;
        expect(challenge.length, 2);
        expect(challenge[1], challenge[0].opposite);
        firsts.add(challenge[0]);
      }
      expect(firsts, {TurnSide.left, TurnSide.right});
    });
  });

  group('getting started', () {
    test('waits until the face is looking straight and well framed', () {
      final sim = _Sim(LivenessSession(challenge: const [TurnSide.left, TurnSide.right]));

      for (var i = 0; i < 20; i++) {
        sim.frame(framing: FaceFraming.offCenter);
      }
      expect(sim.session.phase, LivenessPhase.waitingForFace);

      for (var i = 0; i < 20; i++) {
        sim.frame(yaw: 20, ratio: 0.25);
      }
      expect(sim.session.phase, LivenessPhase.waitingForFace, reason: 'already turned is not "looking straight"');
    });

    test('holding still is interrupted by really moving, and starts over', () {
      final sim = _Sim(LivenessSession(challenge: const [TurnSide.left, TurnSide.right]));
      sim.neutral(ms(400));
      expect(sim.session.phase, LivenessPhase.holdStill);

      for (var i = 0; i < 3; i++) {
        sim.frame(yaw: 20, ratio: 0.25); // 300 ms turned away: longer than the grace
      }
      expect(sim.session.phase, LivenessPhase.waitingForFace);

      sim.neutral(ms(400));
      expect(sim.session.phase, LivenessPhase.holdStill, reason: 'not enough yet');
      sim.neutral(ms(400));
      expect(sim.session.phase, LivenessPhase.turning);
    });

    test('a single noisy frame does not break the hold', () {
      final sim = _Sim(LivenessSession(challenge: const [TurnSide.left, TurnSide.right]));
      sim.neutral(ms(300));
      sim.frame(ratio: 0.23); // a landmark glitch, as seen on the device
      sim.neutral(ms(600));
      expect(sim.session.phase, LivenessPhase.turning);
    });

    test('losing the face before the turns start just waits, it does not fail', () {
      final sim = _Sim(LivenessSession(challenge: const [TurnSide.left, TurnSide.right]));
      sim.neutral(ms(400));

      for (var i = 0; i < 15; i++) {
        sim.frame(faces: 0);
      }
      expect(sim.session.phase, LivenessPhase.waitingForFace);
      expect(sim.session.failure, isNull);
    });

    test('a second person before the turns start just waits', () {
      final sim = _Sim(LivenessSession(challenge: const [TurnSide.left, TurnSide.right]));
      sim.neutral(ms(400));
      sim.frame(faces: 2);
      expect(sim.session.phase, LivenessPhase.waitingForFace);
      expect(sim.session.failure, isNull);
    });

    test('a different face taking over somewhere else before the turns start just restarts', () {
      final sim = _Sim(LivenessSession(challenge: const [TurnSide.left, TurnSide.right]));
      sim.neutral(ms(400), id: 1);
      sim.frame(id: 2, cx: 0.9);
      expect(sim.session.phase, LivenessPhase.waitingForFace);
      expect(sim.session.failure, isNull);
    });
  });

  group('turns', () {
    test('a single frame of a turn is not enough', () {
      final sim = _started();
      sim.turn(TurnSide.left, frames: 1);
      expect(sim.session.turnsCompleted, 0);
      sim.frame();
      sim.turn(TurnSide.left, frames: 1);
      expect(sim.session.turnsCompleted, 0, reason: 'the two frames were not consecutive');
      sim.turn(TurnSide.left, frames: 1);
      expect(sim.session.turnsCompleted, 1);
    });

    test('both the head angle and the nose have to show the turn', () {
      final sim = _started();
      for (var i = 0; i < 6; i++) {
        sim.frame(yaw: 30, ratio: 0.1); // angle big, nose only a little off
      }
      expect(sim.session.turnsCompleted, 0);

      final sim2 = _started();
      for (var i = 0; i < 6; i++) {
        sim2.frame(yaw: 10, ratio: 0.3); // nose off, angle small
      }
      expect(sim2.session.turnsCompleted, 0);
    });

    test('turning the wrong way fails straight away', () {
      final sim = _started();
      sim.turn(TurnSide.right);
      expect(sim.session.phase, LivenessPhase.failed);
      expect(sim.session.failure, LivenessFailure.wrongDirection);
    });

    test('the wrong way on the second turn fails once they have come back through the middle', () {
      final sim = _started();
      sim.turn(TurnSide.left);
      sim.frame();
      sim.turn(TurnSide.left); // asked for right
      expect(sim.session.failure, LivenessFailure.wrongDirection);
    });

    test('the frame kept for each turn is the one closest to the target angle', () {
      final sim = _started(config: const LivenessConfig(turnHold: Duration(milliseconds: 200)));

      sim.frame(yaw: 18.5, ratio: 0.2);
      sim.frame(yaw: 21, ratio: 0.25);
      sim.frame(yaw: 26, ratio: 0.33);

      expect(sim.session.turnsCompleted, 1);
      expect(
        sim.keeps.where((k) => k.role == FrameRole.turnPeak).length,
        2,
        reason: '18.5 then 21 improved it; 26 did not',
      );
      sim.frame();
      sim.turn(TurnSide.right, frames: 3);
      sim.neutral(ms(600));
      expect(sim.session.result!.peakYaws.first, 21);
      expect(sim.session.result!.peakTurnRatios.first, 0.25);
    });

    test('a turn that never lands in the good angle window still keeps a frame', () {
      final sim = _started();
      sim.frame(yaw: 32, ratio: 0.4);
      final keep = sim.frame(yaw: 33, ratio: 0.42);

      expect(sim.session.turnsCompleted, 1);
      expect(keep?.role, FrameRole.turnPeak);
      expect(sim.keeps.where((k) => k.role == FrameRole.turnPeak).length, 1);
    });
  });

  group('finishing', () {
    test('needs a steady look straight before passing, and really drifting restarts it', () {
      final sim = _started();
      sim.turn(TurnSide.left);
      sim.frame();
      sim.turn(TurnSide.right);
      expect(sim.session.phase, LivenessPhase.lookStraight);

      sim.neutral(ms(300));
      expect(sim.session.phase, LivenessPhase.lookStraight);
      for (var i = 0; i < 3; i++) {
        sim.frame(yaw: 15, ratio: 0.12); // drifted for 300 ms
      }
      sim.neutral(ms(300));
      expect(sim.session.phase, LivenessPhase.lookStraight, reason: 'the hold had to start over');
      sim.neutral(ms(300));
      expect(sim.session.phase, LivenessPhase.passed);
    });

    test('one noisy frame while looking straight does not restart the hold', () {
      final sim = _started();
      sim.turn(TurnSide.left);
      sim.frame();
      sim.turn(TurnSide.right);

      sim.neutral(ms(300));
      sim.frame(ratio: 0.22); // glitch
      sim.neutral(ms(300));
      expect(sim.session.phase, LivenessPhase.passed);
    });

    test('a finished session ignores everything after', () {
      final passed = _started();
      passed.turn(TurnSide.left);
      passed.frame();
      passed.turn(TurnSide.right);
      passed.neutral(ms(600));
      expect(passed.session.phase, LivenessPhase.passed);
      passed.frame(faces: 2);
      passed.frame(yaw: 40, ratio: 0.3);
      expect(passed.session.phase, LivenessPhase.passed);
      expect(passed.session.failure, isNull);

      final failed = _started();
      failed.turn(TurnSide.right);
      expect(failed.session.failure, LivenessFailure.wrongDirection);
      failed.neutral(ms(2000));
      failed.turn(TurnSide.left);
      expect(failed.session.phase, LivenessPhase.failed);
      expect(failed.session.failure, LivenessFailure.wrongDirection);
    });
  });

  group('time limits', () {
    test('a turn that never comes times out', () {
      final sim = _started();
      sim.neutral(ms(6200));
      expect(sim.session.failure, LivenessFailure.timeout);
    });

    test('the second turn has its own time limit, starting when the first is done', () {
      final sim = _started();
      sim.neutral(ms(5000));
      expect(sim.session.phase, LivenessPhase.turning);
      sim.turn(TurnSide.left);
      sim.neutral(ms(5000));
      expect(sim.session.phase, LivenessPhase.turning, reason: 'clock restarted');
      sim.neutral(ms(1500));
      expect(sim.session.failure, LivenessFailure.timeout);
    });

    test('looking straight at the end has a limit too', () {
      final sim = _started();
      sim.turn(TurnSide.left);
      sim.frame();
      sim.turn(TurnSide.right);
      sim.frame(yaw: 15, ratio: 0.12);
      for (var i = 0; i < 70; i++) {
        sim.frame(yaw: 15, ratio: 0.12); // never straight
      }
      expect(sim.session.failure, LivenessFailure.timeout);
    });

    test('the whole check has an overall limit', () {
      final sim = _started(config: const LivenessConfig(sessionTimeout: Duration(seconds: 3)));
      sim.neutral(ms(3200));
      expect(sim.session.failure, LivenessFailure.timeout);
    });

    test('a stalled camera is noticed through ticks', () {
      final sim = _started();
      expect(sim.session.onTick(sim.t + ms(100)), isNull);
      expect(sim.session.phase, LivenessPhase.turning);
      sim.session.onTick(sim.t + ms(1200));
      expect(sim.session.failure, LivenessFailure.faceLost);
    });

    test('ticks alone also run out the clock', () {
      final sim = _started();
      sim.session.onTick(sim.t + const Duration(seconds: 7));
      expect(sim.session.failure, LivenessFailure.timeout);
    });
  });

  group('someone or something else in the picture', () {
    test('the face vanishing for a moment is fine, for long is a failure', () {
      final sim = _started();
      for (var i = 0; i < 3; i++) {
        sim.frame(faces: 0);
      }
      expect(sim.session.phase, LivenessPhase.turning);
      sim.turn(TurnSide.left);
      expect(sim.session.turnsCompleted, 1, reason: 'carried on after the blip');

      for (var i = 0; i < 12; i++) {
        sim.frame(faces: 0);
      }
      expect(sim.session.failure, LivenessFailure.faceLost);
    });

    test('a second face fails the check', () {
      final sim = _started();
      sim.frame(faces: 2);
      expect(sim.session.failure, LivenessFailure.multipleFaces);
    });

    test('a different tracked face that appears somewhere else fails the check', () {
      final sim = _started();
      sim.turn(TurnSide.left);
      sim.frame(id: 9, cx: 0.8, cy: 0.5);
      expect(sim.session.failure, LivenessFailure.faceChanged);
    });

    test('the tracker re-numbering the same face, straight away and in the same place, is fine', () {
      final sim = _started();
      sim.frame(yaw: 10, ratio: 0.1, id: 1, cx: 0.5);
      sim.frame(yaw: 15, ratio: 0.2, id: 2, cx: 0.48); // new id, barely moved, 100 ms later
      expect(sim.session.failure, isNull);

      // ...and the check carries on under the new id.
      sim.turn(TurnSide.left, id: 2);
      expect(sim.session.turnsCompleted, 1);
      sim.frame(id: 2);
      sim.frame(id: 1);
      expect(sim.session.failure, isNull, reason: 'going back to the old id is another re-numbering, still in place');
    });

    test('a new id after the face was gone a while is a different face', () {
      final sim = _started();
      sim.frame(faces: 0);
      sim.frame(faces: 0);
      sim.frame(faces: 0);
      sim.frame(faces: 0, ms: 300); // ~0.75 s without a face, still inside the loss grace
      sim.frame(id: 5, ms: 700); // back after 1.4 s in total, under a new id
      expect(sim.session.failure, LivenessFailure.faceChanged);
    });

    test('the swapped-in picture case: new id and the face box jumped down the frame', () {
      final sim = _started();
      sim.frame(id: 1, cx: 0.49, cy: 0.51);
      sim.frame(id: 143, cx: 0.42, cy: 0.77); // seen on a device: 0.26 lower in one frame
      expect(sim.session.failure, LivenessFailure.faceChanged);
    });

    test('a head angle that jumps further than a head can move fails', () {
      final sim = _started();
      sim.frame(yaw: 2);
      sim.frame(yaw: 50, ratio: 0.5);
      expect(sim.session.failure, LivenessFailure.implausibleMotion);
    });

    test('angle says turned but the nose does not move: a flat picture being rotated', () {
      final sim = _started();
      for (var i = 0; i < 4; i++) {
        sim.frame(yaw: 22, ratio: 0.01);
      }
      expect(sim.session.failure, LivenessFailure.notLive);
    });

    test('a few odd frames are tolerated, only a run of disagreement fails', () {
      final sim = _started();
      sim.frame(yaw: 22, ratio: 0.01);
      sim.frame(yaw: 22, ratio: 0.01);
      sim.frame(yaw: 22, ratio: 0.01);
      sim.frame(yaw: 22, ratio: 0.25); // agrees again
      sim.frame(yaw: 22, ratio: 0.01);
      sim.frame(yaw: 22, ratio: 0.01);
      expect(sim.session.failure, isNull);
    });

    test('head angle and nose that stop moving together fail', () {
      final sim = _started();
      sim.turn(TurnSide.left); // angle +, nose +
      sim.frame();
      sim.frame(yaw: 22, ratio: -0.25); // nose says right, angle still says the same as before
      sim.frame(yaw: 22, ratio: -0.25);
      expect(sim.session.failure, LivenessFailure.notLive);
    });
  });

  group('a person whose straight-ahead reading is not zero', () {
    // Measured on a real phone: looking straight the nose sat around -0.05 and
    // the angle a couple of degrees off, and that differs from person to person.
    _Sim person({double yaw = 1.5, double ratio = -0.06}) {
      final sim = _Sim(LivenessSession(challenge: const [TurnSide.left, TurnSide.right]))
        ..baseYaw = yaw
        ..baseRatio = ratio;
      return sim;
    }

    test('can still start, turn and pass, because turns are measured from their own baseline', () {
      final sim = person();
      sim.neutral(ms(800));
      expect(sim.session.phase, LivenessPhase.turning);
      expect(sim.session.baselineRatio, closeTo(-0.06, 1e-9));
      expect(sim.session.baselineYaw, closeTo(1.5, 1e-9));

      sim.turn(TurnSide.left);
      sim.frame();
      sim.turn(TurnSide.right);
      sim.neutral(ms(600));

      expect(sim.session.phase, LivenessPhase.passed);
      final r = sim.session.result!;
      expect(r.baselineRatio, closeTo(-0.06, 1e-9));
      expect(r.peakTurnRatios, [0.25, -0.25], reason: 'peaks are reported relative to the baseline');
    });

    test('a turn that is only the baseline moving a little does not count', () {
      final sim = person(ratio: -0.06);
      sim.neutral(ms(800));
      for (var i = 0; i < 10; i++) {
        sim.frame(yaw: 30, ratio: 0.1); // relative nose move 0.1 < 0.15
      }
      expect(sim.session.turnsCompleted, 0);
    });

    test('the baseline is the middle reading of the hold, so a glitch in it does not skew it', () {
      final sim = person(ratio: 0);
      sim.neutral(ms(300));
      sim.frame(ratio: 0.23); // glitch inside the hold window
      sim.neutral(ms(600));
      expect(sim.session.baselineRatio, closeTo(0, 1e-9));
    });

    test('will not start when the nose is already far off centre (an already-turned head)', () {
      final sim = _Sim(LivenessSession(challenge: const [TurnSide.left, TurnSide.right]));
      for (var i = 0; i < 20; i++) {
        sim.frame(yaw: 3, ratio: 0.24);
      }
      expect(sim.session.phase, LivenessPhase.waitingForFace);
    });
  });

  group('timing does not depend on the frame rate', () {
    test('at 28 frames a second a turn is done after 100 ms of holding it, not after two frames', () {
      final sim = _Sim(LivenessSession(challenge: const [TurnSide.left, TurnSide.right]))..stepMs = 35;
      sim.neutral(ms(800));
      expect(sim.session.phase, LivenessPhase.turning);

      sim.turn(TurnSide.left, frames: 2); // 35 ms
      expect(sim.session.turnsCompleted, 0);
      sim.turn(TurnSide.left, frames: 2); // 105 ms since the first
      expect(sim.session.turnsCompleted, 1);
    });

    test('the flat-picture check needs the disagreement to last, however many frames that is', () {
      final sim = _Sim(LivenessSession(challenge: const [TurnSide.left, TurnSide.right]))..stepMs = 35;
      sim.neutral(ms(800));
      for (var i = 0; i < 6; i++) {
        sim.frame(yaw: 22, ratio: 0.01); // 6 frames = 175 ms < 300 ms
      }
      expect(sim.session.failure, isNull);
      for (var i = 0; i < 6; i++) {
        sim.frame(yaw: 22, ratio: 0.01);
      }
      expect(sim.session.failure, LivenessFailure.notLive);
    });
  });

  group('what the real-phone runs changed', () {
    test('a clear turn of about 16 degrees counts (an 18 degree minimum rejected an honest turn)', () {
      final sim = _started(challenge: const [TurnSide.right, TurnSide.left]);

      sim.turn(TurnSide.right, yaw: 16, ratio: 0.2);

      expect(sim.session.turnsCompleted, 1);
      expect(sim.session.failure, isNull);
    });

    test('but the head angle alone still is not a turn: the nose has to move too', () {
      final sim = _started();
      for (var i = 0; i < 12; i++) {
        sim.frame(yaw: 16, ratio: 0.09); // angle enough, nose barely
      }
      expect(sim.session.turnsCompleted, 0);
    });

    test('a very far turn with an exploded nose reading is not mistaken for the wrong direction', () {
      final sim = _started(challenge: const [TurnSide.left, TurnSide.right]);
      sim.frame(yaw: 30, ratio: 0.4); // turning left, as asked
      // Far past a sensible angle the nose offset flipped sign on a device.
      sim.frame(yaw: 62, ratio: -0.9);
      sim.frame(yaw: 66, ratio: -1.0);
      expect(sim.session.failure, isNull);

      sim.frame(yaw: 50, ratio: 0.6); // back down, a step at a time
      sim.frame(yaw: 30, ratio: 0.4);
      sim.turn(TurnSide.left, frames: 2); // in range again, still turned left
      expect(sim.session.turnsCompleted, 1);
    });
  });

  group('how far the current hold has got', () {
    test('is nothing before the hold starts, fills while holding still, and is full once passed', () {
      final sim = _Sim(LivenessSession(challenge: const [TurnSide.left, TurnSide.right]));
      expect(sim.session.holdProgress, 0);

      sim.frame(); // the hold starts
      sim.frame();
      final early = sim.session.holdProgress;
      sim.frame();
      sim.frame();
      sim.frame();
      final later = sim.session.holdProgress;

      expect(early, greaterThan(0));
      expect(later, greaterThan(early));
      expect(later, lessThan(1));

      sim.neutral(ms(300));
      sim.turn(TurnSide.left);
      sim.frame();
      sim.turn(TurnSide.right);
      sim.neutral(ms(600));
      expect(sim.session.phase, LivenessPhase.passed);
      expect(sim.session.holdProgress, 1);
    });

    test('is nothing while turning', () {
      final sim = _started();
      expect(sim.session.holdProgress, 0);
      sim.turn(TurnSide.left, frames: 1);
      expect(sim.session.holdProgress, 0);
    });

    test('fills during the final look straight, and starts over if the head drifts', () {
      final sim = _started();
      sim.turn(TurnSide.left);
      sim.frame();
      sim.turn(TurnSide.right);
      expect(sim.session.phase, LivenessPhase.lookStraight);
      expect(sim.session.holdProgress, 0);

      sim.neutral(ms(300));
      final part = sim.session.holdProgress;
      expect(part, greaterThan(0.3));
      expect(part, lessThan(1));

      for (var i = 0; i < 3; i++) {
        sim.frame(yaw: 15, ratio: 0.12); // drifted off straight for longer than the grace
      }
      expect(sim.session.holdProgress, 0);
    });

    test('is nothing after a failure', () {
      final sim = _started();
      sim.turn(TurnSide.right);
      expect(sim.session.phase, LivenessPhase.failed);
      expect(sim.session.holdProgress, 0);
    });
  });
}
