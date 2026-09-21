import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/services/liveness/direction_test.dart';
import 'package:frontend/services/liveness/face_observation.dart';

/// Runs a whole test with the person's raw nose readings for each stage.
DirectionTest _run({
  required double straight,
  required double left,
  required double right,
  double straightAgain = 0,
  bool faceVisibleInTurns = true,
}) {
  final test = DirectionTest();
  var t = Duration.zero;
  var i = 0;

  void feed(double ratio, {bool visible = true}) {
    t += const Duration(milliseconds: 100);
    final o = visible
        ? FaceObservation(at: t, frameIndex: i++, faceCount: 1, yawDegrees: 0, turnRatio: ratio)
        : FaceObservation.noFace(at: t, frameIndex: i++);
    test.onObservation(o, rawRatio: visible ? ratio : null);
  }

  // Each stage lasts a fixed time, so feed until the stage changes.
  void hold(DirectionTestStage stage, double ratio, {bool visible = true}) {
    while (test.stage == stage && !test.isDone) {
      feed(ratio, visible: visible);
    }
  }

  hold(DirectionTestStage.straight, straight);
  hold(DirectionTestStage.left, left, visible: faceVisibleInTurns);
  hold(DirectionTestStage.straightAgain, straightAgain);
  hold(DirectionTestStage.right, right, visible: faceVisibleInTurns);
  return test;
}

void main() {
  test('walks through the stages, telling the person what to do', () {
    final test = DirectionTest();
    expect(test.stage, DirectionTestStage.straight);
    expect(test.prompt, contains('straight'));

    var t = Duration.zero;
    final prompts = <String>[test.prompt];
    for (var i = 0; i < 80 && !test.isDone; i++) {
      t += const Duration(milliseconds: 100);
      final before = test.stage;
      test.onObservation(FaceObservation(at: t, frameIndex: i, faceCount: 1, yawDegrees: 0, turnRatio: 0), rawRatio: 0);
      if (test.stage != before) prompts.add(test.prompt);
    }
    expect(prompts, [
      'Look straight at the camera',
      'Turn to YOUR LEFT and hold',
      'Look straight again',
      'Turn to YOUR RIGHT and hold',
      'Try again', // nobody actually turned, so there is no conclusion
    ]);
  });

  group('the result', () {
    test('a device whose frames are not mirrored: your left moves the nose toward the frame right', () {
      final result = _run(straight: -0.05, left: 0.25, right: -0.35).result!;

      expect(result.conclusive, isTrue);
      expect(result.framesMirrored, isFalse);
      expect(result.baseline, closeTo(-0.05, 1e-9));
      expect(result.leftMove, closeTo(0.30, 1e-9));
      expect(result.rightMove, closeTo(-0.30, 1e-9));
    });

    test('a device whose frames are mirrored: your left moves the nose toward the frame left', () {
      final result = _run(straight: 0.04, left: -0.3, right: 0.36).result!;

      expect(result.conclusive, isTrue);
      expect(result.framesMirrored, isTrue);
    });

    test('a personal straight-ahead offset does not matter, only the moves from it', () {
      // Nose sits at +0.20 when straight; turning left goes to +0.5, right to -0.1.
      final result = _run(straight: 0.2, left: 0.5, right: -0.1).result!;

      expect(result.framesMirrored, isFalse);
    });

    test('a turn that is too small is inconclusive', () {
      final result = _run(straight: 0, left: 0.05, right: -0.06).result!;

      expect(result.conclusive, isFalse);
      expect(result.framesMirrored, isNull);
      expect(result.summary, contains('Inconclusive'));
    });

    test('both turns moving the nose the same way is inconclusive, not a guess', () {
      final result = _run(straight: 0, left: 0.3, right: 0.3).result!;

      expect(result.conclusive, isFalse);
    });

    test('not being visible during the turns is inconclusive', () {
      final result = _run(straight: 0, left: 0.3, right: -0.3, faceVisibleInTurns: false).result!;

      expect(result.conclusive, isFalse);
    });

    test('the furthest reading in a turn counts, not the last one', () {
      // Peaks at 0.4 then relaxes back towards 0.1 while still "turning".
      final test = DirectionTest();
      var t = Duration.zero;
      var i = 0;
      void feed(double r) {
        t += const Duration(milliseconds: 100);
        test.onObservation(
          FaceObservation(at: t, frameIndex: i++, faceCount: 1, yawDegrees: 0, turnRatio: r),
          rawRatio: r,
        );
      }

      while (test.stage == DirectionTestStage.straight) {
        feed(0);
      }
      for (final r in [0.1, 0.2, 0.4, 0.3, 0.1]) {
        feed(r);
      }
      while (test.stage == DirectionTestStage.left) {
        feed(0.1);
      }
      while (test.stage == DirectionTestStage.straightAgain) {
        feed(0);
      }
      while (test.stage == DirectionTestStage.right) {
        feed(-0.35);
      }

      expect(test.result!.leftMove, closeTo(0.4, 1e-9));
      expect(test.result!.framesMirrored, isFalse);
    });
  });

  test('rawRatioOf undoes the mirroring the analyzer applied', () {
    const o = FaceObservation(at: Duration.zero, frameIndex: 0, faceCount: 1, yawDegrees: 0, turnRatio: 0.3);
    expect(rawRatioOf(o, framesMirrored: false), 0.3);
    expect(rawRatioOf(o, framesMirrored: true), -0.3);
    expect(rawRatioOf(FaceObservation.noFace(at: Duration.zero, frameIndex: 0), framesMirrored: false), isNull);
  });

  test('a finished test ignores further frames', () {
    final test = _run(straight: 0, left: 0.3, right: -0.3);
    final result = test.result;
    test.onObservation(
      FaceObservation(at: const Duration(seconds: 99), frameIndex: 999, faceCount: 1, yawDegrees: 0, turnRatio: 5),
      rawRatio: 5,
    );
    expect(test.result, same(result));
  });
}
