import 'dart:math';

/// Cosine similarity of two embeddings, -1..1. Embeddings of different lengths
/// (an enrolment made by an older model) or with no length score 0, so they can
/// never match.
double cosineSimilarity(List<double> a, List<double> b) {
  if (a.length != b.length || a.isEmpty) return 0;

  double dot = 0, normA = 0, normB = 0;
  for (var i = 0; i < a.length; i++) {
    dot += a[i] * b[i];
    normA += a[i] * a[i];
    normB += b[i] * b[i];
  }
  if (normA == 0 || normB == 0) return 0;
  return dot / (sqrt(normA) * sqrt(normB));
}

/// The average of several embeddings of the same face, scaled back to unit
/// length. One video frame is noisy (blur, exposure, a blink); the average of a
/// few in a row is steadier, so it matches the enrolled face more reliably.
/// Embeddings of different lengths, or none, cannot be averaged.
List<double> averageEmbeddings(List<List<double>> embeddings) {
  if (embeddings.isEmpty) throw ArgumentError('nothing to average');
  final length = embeddings.first.length;
  if (embeddings.any((e) => e.length != length)) throw ArgumentError('embeddings differ in length');

  final mean = List<double>.filled(length, 0);
  for (final embedding in embeddings) {
    for (var i = 0; i < length; i++) {
      mean[i] += embedding[i] / embeddings.length;
    }
  }
  final norm = sqrt(mean.fold<double>(0, (sum, v) => sum + v * v));
  if (norm == 0 || !norm.isFinite) throw ArgumentError('embeddings cancel out');
  return [for (final v in mean) v / norm];
}
