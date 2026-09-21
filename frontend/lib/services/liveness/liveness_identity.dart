import '../face_similarity.dart';

/// Why a head-turn check that was passed still can't count for this person.
enum IdentityFailure {
  /// One of the frames the check should have kept is missing.
  missingFrames,

  /// The face at the end doesn't match this person's enrolled faces.
  noMatch,

  /// The frames from the turns aren't the person seen at the end: someone else
  /// (or a picture) was swapped in after the turns.
  differentPerson,
}

class LivenessIdentityResult {
  const LivenessIdentityResult({required this.similarityToEnrolled, this.failure, this.lowestSameFace});

  /// Best score of the final frame against the person's enrolled faces.
  final double similarityToEnrolled;

  /// The weakest score any other frame had against the final frame (how alike
  /// the person looked throughout), or null if there were none to compare.
  final double? lowestSameFace;

  final IdentityFailure? failure;

  bool get passed => failure == null;
}

/// The identity rule for a passed head-turn check.
///
/// The check proves someone live turned their head. That is only worth
/// something if it is the same person who is then recorded, so:
///
/// 1. the final straight frame (also the attendance photo) must match the
///    person's enrolled faces, like any attendance photo — best score across
///    their templates, at [matchThreshold];
/// 2. every other frame kept from the check (before the turns, at each turn)
///    must be the same person as that final frame, at [sameFaceMin]. A photo
///    or a colleague swapped in after the turns fails here.
///
/// Turned frames are not held to the full match threshold: faces turned 20°
/// score lower for a real reason, and that limit is left for calibration.
LivenessIdentityResult evaluateLivenessIdentity({
  required List<double>? finalEmbedding,
  required List<List<double>> otherEmbeddings,
  required List<List<double>> templates,
  required double matchThreshold,
  required double sameFaceMin,
  int expectedOthers = 3,
}) {
  final finalFrame = finalEmbedding;
  if (finalFrame == null || otherEmbeddings.length < expectedOthers) {
    return const LivenessIdentityResult(similarityToEnrolled: 0, failure: IdentityFailure.missingFrames);
  }

  var best = 0.0;
  for (var i = 0; i < templates.length; i++) {
    final similarity = cosineSimilarity(templates[i], finalFrame);
    if (i == 0 || similarity > best) best = similarity;
  }
  final matched = templates.isNotEmpty && best >= matchThreshold;

  double? lowest;
  for (final other in otherEmbeddings) {
    final similarity = cosineSimilarity(other, finalFrame);
    if (lowest == null || similarity < lowest) lowest = similarity;
  }

  if (!matched) {
    return LivenessIdentityResult(similarityToEnrolled: best, lowestSameFace: lowest, failure: IdentityFailure.noMatch);
  }
  if (lowest != null && lowest < sameFaceMin) {
    return LivenessIdentityResult(
      similarityToEnrolled: best,
      lowestSameFace: lowest,
      failure: IdentityFailure.differentPerson,
    );
  }
  return LivenessIdentityResult(similarityToEnrolled: best, lowestSameFace: lowest);
}
