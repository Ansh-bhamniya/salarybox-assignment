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
  const FaceSample({
    required this.embedding,
    required this.imagePath,
    this.yawDegrees,
    this.faceCenterX,
    this.faceCenterY,
    this.faceWidthRatio,
  });

  final List<double> embedding;
  final String imagePath;

  /// ML Kit's head angle (Euler Y) on the photo, in degrees; only its size is
  /// meaningful across photos. Null when unknown.
  final double? yawDegrees;

  /// Where the face sits on the photo, as fractions of it (centre from the left
  /// and top, width across), so a photo where the person wasn't in the frame
  /// can be told apart. Null when unknown.
  final double? faceCenterX;
  final double? faceCenterY;
  final double? faceWidthRatio;
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
