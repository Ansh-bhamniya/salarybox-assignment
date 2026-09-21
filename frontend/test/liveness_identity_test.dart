import 'dart:math';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/services/liveness/liveness_identity.dart';

/// A unit vector whose cosine with axis 0 is [cos] (living in the first two dimensions).
List<double> _atCos(double cos) => List<double>.filled(8, 0)
  ..[0] = cos
  ..[1] = sqrt(1 - cos * cos);
List<double> _axis(int i) => List<double>.filled(8, 0)..[i] = 1;

LivenessIdentityResult _check({
  List<double>? finalFrame,
  List<List<double>>? others,
  List<List<double>>? templates,
  double match = 0.55,
  double same = 0.4,
}) => evaluateLivenessIdentity(
  finalEmbedding: finalFrame ?? _axis(0),
  otherEmbeddings: others ?? [_atCos(0.9), _atCos(0.8), _atCos(0.7)],
  templates: templates ?? [_axis(0)],
  matchThreshold: match,
  sameFaceMin: same,
);

void main() {
  group('a passed check counts when the same person is recorded', () {
    test('final frame matches the enrolled face and the other frames look like it', () {
      final result = _check();

      expect(result.passed, isTrue);
      expect(result.failure, isNull);
      expect(result.similarityToEnrolled, closeTo(1, 1e-9));
      expect(result.lowestSameFace, closeTo(0.7, 1e-9));
    });

    test('the best of several enrolled faces is used', () {
      final result = _check(finalFrame: _atCos(0.9), templates: [_axis(5), _axis(0), _axis(6)]);

      expect(result.passed, isTrue);
      expect(result.similarityToEnrolled, closeTo(0.9, 1e-9));
    });

    test('turned frames need not match the enrolled face as strongly as the final one', () {
      // Turned frames score 0.5 against the final frame: fine, they are only held to the same-person limit.
      final result = _check(others: [_atCos(0.5), _atCos(0.5), _atCos(0.5)]);
      expect(result.passed, isTrue);
    });
  });

  group('and does not count when it is not', () {
    test('the final frame does not match the enrolled face', () {
      final result = _check(finalFrame: _atCos(0.3));

      expect(result.passed, isFalse);
      expect(result.failure, IdentityFailure.noMatch);
      expect(result.similarityToEnrolled, closeTo(0.3, 1e-9));
    });

    test('a colleague or a photo swapped in after the turns: the earlier frames are someone else', () {
      // The final frame IS the enrolled person (a photo of them), but the frames from the turns were
      // someone else, scoring 0.1 against it.
      final result = _check(others: [_atCos(0.1), _atCos(0.85), _atCos(0.8)]);

      expect(result.passed, isFalse);
      expect(result.failure, IdentityFailure.differentPerson);
      expect(result.lowestSameFace, closeTo(0.1, 1e-9));
    });

    test('a single odd frame among the others is enough to fail it', () {
      final result = _check(others: [_atCos(0.9), _atCos(0.35), _atCos(0.9)]);
      expect(result.failure, IdentityFailure.differentPerson);
    });

    test('no match is reported ahead of a mismatch between frames', () {
      final result = _check(finalFrame: _atCos(0.2), others: [_atCos(0.0), _atCos(0.0), _atCos(0.0)]);
      expect(result.failure, IdentityFailure.noMatch);
    });

    test('a person with no usable enrolled faces cannot match', () {
      expect(_check(templates: []).failure, IdentityFailure.noMatch);
      // A legacy short embedding scores 0 against a full one.
      expect(_check(templates: [List<double>.filled(3, 1)]).failure, IdentityFailure.noMatch);
    });
  });

  group('limits', () {
    test('the match limit is inclusive', () {
      expect(_check(finalFrame: _atCos(0.55)).passed, isTrue);
      expect(_check(finalFrame: _atCos(0.549)).failure, IdentityFailure.noMatch);
    });

    test('the same-person limit is inclusive', () {
      expect(_check(others: [_atCos(0.4), _atCos(0.9), _atCos(0.9)]).passed, isTrue);
      expect(_check(others: [_atCos(0.399), _atCos(0.9), _atCos(0.9)]).failure, IdentityFailure.differentPerson);
    });
  });

  group('frames that never arrived', () {
    test('no final frame', () {
      final result = evaluateLivenessIdentity(
        finalEmbedding: null,
        otherEmbeddings: [_axis(0), _axis(0), _axis(0)],
        templates: [_axis(0)],
        matchThreshold: 0.55,
        sameFaceMin: 0.4,
      );
      expect(result.failure, IdentityFailure.missingFrames);
      expect(result.passed, isFalse);
    });

    test('fewer than the start frame and two turn frames', () {
      expect(_check(others: [_atCos(0.9), _atCos(0.9)]).failure, IdentityFailure.missingFrames);
      expect(_check(others: []).failure, IdentityFailure.missingFrames);
    });

    test('how many are expected is configurable', () {
      final result = evaluateLivenessIdentity(
        finalEmbedding: _axis(0),
        otherEmbeddings: [_atCos(0.9)],
        templates: [_axis(0)],
        matchThreshold: 0.55,
        sameFaceMin: 0.4,
        expectedOthers: 1,
      );
      expect(result.passed, isTrue);
    });
  });
}
