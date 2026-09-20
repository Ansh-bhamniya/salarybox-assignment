class FaceMatchResult {
  const FaceMatchResult({required this.isMatch, required this.similarity});

  final bool isMatch;
  final double similarity;
}

/// What a successfully processed selfie yields: the embedding, and the path
/// of the upright, size-normalized JPEG it was computed from. That file (not
/// the raw camera file) is what gets previewed and uploaded, so the stored
/// photo is always the right way up and a sensible size.
class FaceSample {
  const FaceSample({required this.embedding, required this.imagePath});

  final List<double> embedding;
  final String imagePath;
}

/// Thrown by [FaceEmbeddingService] whenever it can't turn a photo into an
/// embedding — no face found, more than one face, or required landmarks
/// missing (e.g. a face turned too far from the camera).
class FaceProcessingException implements Exception {
  FaceProcessingException(this.message);
  final String message;

  @override
  String toString() => message;
}
