/// One captured face of a staff member, as produced by one version of the
/// face model. Templates from different model versions are never compared.
class FaceTemplate {
  const FaceTemplate({required this.modelVersion, required this.embedding});

  /// Assumed for a backend that predates versioned templates.
  static const legacyModelVersion = 'mobilefacenet-192-v1';

  final String modelVersion;
  final List<double> embedding;
}

class Staff {
  const Staff({
    required this.id,
    required this.employeeId,
    required this.name,
    this.enrollmentPhotoUrl,
    this.enrolledAt,
    this.faceTemplates = const [],
    bool? enrolled,
  }) : _enrolled = enrolled;

  final String id;
  final String employeeId;
  final String name;
  final String? enrollmentPhotoUrl;
  final DateTime? enrolledAt;

  /// The person's active face templates, frontal shot first. Empty when the
  /// backend didn't send them (list endpoints leave them out).
  final List<FaceTemplate> faceTemplates;

  final bool? _enrolled;

  /// The first template's embedding — what a single-template backend sent.
  List<double>? get faceEmbedding => faceTemplates.isEmpty ? null : faceTemplates.first.embedding;

  /// The embeddings made by [modelVersion], the only ones this app build can compare against.
  List<List<double>> embeddingsFor(String modelVersion) => [
    for (final template in faceTemplates)
      if (template.modelVersion == modelVersion) template.embedding,
  ];

  /// Whether the person has an active face template. The backend says so
  /// explicitly; the photo check only covers a backend that predates the flag.
  bool get isEnrolled => _enrolled ?? enrollmentPhotoUrl != null;

  static List<double> _toDoubles(Object? raw) => (raw as List<dynamic>).map((e) => (e as num).toDouble()).toList();

  static Staff fromJson(Map<String, dynamic> json) {
    final templates = json['face_templates'] as List<dynamic>?;
    final legacyEmbedding = json['face_embedding'];

    return Staff(
      id: json['id'] as String,
      employeeId: json['employee_id'] as String,
      name: json['name'] as String,
      enrollmentPhotoUrl: json['enrollment_photo_url'] as String?,
      enrolledAt: json['enrolled_at'] != null ? DateTime.parse(json['enrolled_at'] as String) : null,
      enrolled: json['enrolled'] as bool?,
      faceTemplates: templates != null
          ? [
              for (final t in templates.cast<Map<String, dynamic>>())
                FaceTemplate(
                  modelVersion: t['model_version'] as String? ?? FaceTemplate.legacyModelVersion,
                  embedding: _toDoubles(t['embedding']),
                ),
            ]
          : [
              // A backend that predates multiple templates: one embedding, one model.
              if (legacyEmbedding != null)
                FaceTemplate(modelVersion: FaceTemplate.legacyModelVersion, embedding: _toDoubles(legacyEmbedding)),
            ],
    );
  }
}
