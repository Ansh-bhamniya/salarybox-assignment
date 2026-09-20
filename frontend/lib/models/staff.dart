class Staff {
  const Staff({
    required this.id,
    required this.employeeId,
    required this.name,
    this.enrollmentPhotoUrl,
    this.enrolledAt,
    this.faceEmbedding,
    bool? enrolled,
  }) : _enrolled = enrolled;

  final String id;
  final String employeeId;
  final String name;
  final String? enrollmentPhotoUrl;
  final DateTime? enrolledAt;
  final List<double>? faceEmbedding;

  final bool? _enrolled;

  /// Whether the person has an active face template. The backend says so
  /// explicitly; the photo check only covers a backend that predates the flag.
  bool get isEnrolled => _enrolled ?? enrollmentPhotoUrl != null;

  static Staff fromJson(Map<String, dynamic> json) => Staff(
    id: json['id'] as String,
    employeeId: json['employee_id'] as String,
    name: json['name'] as String,
    enrollmentPhotoUrl: json['enrollment_photo_url'] as String?,
    enrolledAt: json['enrolled_at'] != null ? DateTime.parse(json['enrolled_at'] as String) : null,
    enrolled: json['enrolled'] as bool?,
    faceEmbedding: (json['face_embedding'] as List<dynamic>?)?.map((e) => (e as num).toDouble()).toList(),
  );
}
