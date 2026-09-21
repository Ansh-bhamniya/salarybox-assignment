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
}
