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
}
