import 'dart:math';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/services/face_similarity.dart';

List<double> _axis(int i) => List<double>.filled(8, 0)..[i] = 1;

void main() {
  group('cosineSimilarity', () {
    test('identical is 1, orthogonal 0, opposite -1', () {
      expect(cosineSimilarity(_axis(0), _axis(0)), closeTo(1, 1e-9));
      expect(cosineSimilarity(_axis(0), _axis(1)), 0);
      expect(cosineSimilarity(_axis(0), _axis(0).map((v) => -v).toList()), closeTo(-1, 1e-9));
    });

    test('different lengths, empty and all-zero score 0 rather than throwing', () {
      expect(cosineSimilarity([1, 0], [1, 0, 0]), 0);
      expect(cosineSimilarity([], []), 0);
      expect(cosineSimilarity([0, 0], [1, 0]), 0);
    });
  });

  group('averageEmbeddings', () {
    test('the average of identical embeddings is that embedding', () {
      final avg = averageEmbeddings([_axis(0), _axis(0), _axis(0)]);
      expect(avg[0], closeTo(1, 1e-9));
      expect(avg.skip(1).every((v) => v == 0), isTrue);
    });

    test('is scaled back to unit length', () {
      final avg = averageEmbeddings([_axis(0), _axis(1)]);
      final norm = sqrt(avg.fold<double>(0, (s, v) => s + v * v));
      expect(norm, closeTo(1, 1e-9));
      expect(avg[0], closeTo(1 / sqrt(2), 1e-9));
      expect(avg[1], closeTo(1 / sqrt(2), 1e-9));
    });

    test('sits between its inputs: an outlier is pulled toward the rest', () {
      final avg = averageEmbeddings([_axis(0), _axis(0), _axis(0), _axis(0), _axis(2)]);
      expect(cosineSimilarity(avg, _axis(0)), closeTo(0.8 / sqrt(0.68), 1e-9));
      expect(cosineSimilarity(avg, _axis(0)), greaterThan(0.95));
    });

    test('refuses what cannot be averaged', () {
      expect(() => averageEmbeddings([]), throwsArgumentError);
      expect(
        () => averageEmbeddings([
          [1, 0],
          [1, 0, 0],
        ]),
        throwsArgumentError,
      );
      expect(
        () => averageEmbeddings([
          [1, 0],
          [-1, 0],
        ]),
        throwsArgumentError,
        reason: 'they cancel out',
      );
    });
  });
}
