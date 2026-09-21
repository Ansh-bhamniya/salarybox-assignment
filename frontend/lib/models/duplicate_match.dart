/// Another staff member whose enrolled face looks like the one being enrolled,
/// as reported by the backend when it refuses a duplicate (`duplicate_face`).
class DuplicateMatch {
  const DuplicateMatch({required this.name, required this.employeeId, required this.similarity});

  final String name;
  final String employeeId;

  /// Cosine similarity, 0..1 for real faces.
  final double similarity;

  /// Reads the `details` of a `duplicate_face` error; anything unexpected yields an empty list.
  static List<DuplicateMatch> listFrom(Object? details) {
    if (details is! Map || details['matches'] is! List) return const [];
    return [
      for (final m in (details['matches'] as List).whereType<Map>())
        DuplicateMatch(
          name: m['name'] as String? ?? 'another staff member',
          employeeId: m['employeeId'] as String? ?? '',
          similarity: (m['similarity'] as num?)?.toDouble() ?? 0,
        ),
    ];
  }
}
