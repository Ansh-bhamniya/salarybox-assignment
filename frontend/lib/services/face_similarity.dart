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
