import 'dart:math';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/config/env.dart';
import 'package:frontend/services/face_embedding_service.dart';

void main() {
  final service = FaceEmbeddingService();

  List<double> unit(List<double> v) {
    final norm = sqrt(v.fold<double>(0, (s, x) => s + x * x));
    return v.map((x) => x / norm).toList();
  }

  test('identical embeddings match with similarity 1', () {
    final e = unit(List.generate(192, (i) => (i % 7) - 3.0));
    final result = service.compare(e, e);
    expect(result.similarity, closeTo(1.0, 1e-9));
    expect(result.isMatch, isTrue);
  });

  test('unrelated (orthogonal) embeddings do not match', () {
    final a = List<double>.filled(192, 0)..[0] = 1;
    final b = List<double>.filled(192, 0)..[1] = 1;
    final result = service.compare(a, b);
    expect(result.similarity, 0);
    expect(result.isMatch, isFalse);
  });

  test('threshold is inclusive', () {
    const t = Env.faceMatchThreshold;
    // cos == t for these two unit vectors, which live in the first two dimensions.
    final a = List<double>.filled(192, 0)..[0] = 1;
    final b = List<double>.filled(192, 0)
      ..[0] = t
      ..[1] = sqrt(1 - t * t);
    expect(service.compare(a, b).isMatch, isTrue);
  });

  test('a legacy 8-value enrolment can never match a 192-value embedding', () {
    final legacy = List<double>.filled(8, 1.0);
    final fresh = unit(List.generate(192, (i) => 1.0 + i));
    final result = service.compare(legacy, fresh);
    expect(result.similarity, 0);
    expect(result.isMatch, isFalse);
  });

  test('empty or all-zero embeddings never match', () {
    expect(service.compare(const [], const []).isMatch, isFalse);
    expect(service.compare(List.filled(192, 0.0), List.filled(192, 1.0)).isMatch, isFalse);
  });

  group('compareToAny (several enrolled templates)', () {
    const t = Env.faceMatchThreshold;
    List<double> axis(int i) => List<double>.filled(192, 0)..[i] = 1;
    // Unit vector whose cosine with axis(0) is `cos`.
    List<double> atCos(double cos) => List<double>.filled(192, 0)
      ..[0] = cos
      ..[1] = sqrt(1 - cos * cos);

    test('the best template decides, so one good capture is enough', () {
      final fresh = atCos(0.9);
      final result = service.compareToAny([axis(5), axis(0), axis(7)], fresh);
      expect(result.similarity, closeTo(0.9, 1e-9));
      expect(result.isMatch, isTrue);
    });

    test('no template close enough means no match, and reports the best score', () {
      final fresh = atCos(t - 0.1);
      final result = service.compareToAny([axis(0), axis(5)], fresh);
      expect(result.similarity, closeTo(t - 0.1, 1e-9));
      expect(result.isMatch, isFalse);
    });

    test('a negative best score is reported as-is, not clamped to zero', () {
      final result = service.compareToAny([atCos(-0.4)], axis(0));
      expect(result.similarity, closeTo(-0.4, 1e-9));
      expect(result.isMatch, isFalse);
    });

    test('no templates never match', () {
      final result = service.compareToAny([], axis(0));
      expect(result.isMatch, isFalse);
    });

    test('compare() is compareToAny with one template', () {
      final a = axis(0), b = atCos(0.7);
      expect(service.compare(a, b).similarity, service.compareToAny([a], b).similarity);
    });
  });
}
