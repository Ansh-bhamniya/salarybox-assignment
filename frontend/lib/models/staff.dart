class Staff {
  const Staff({
    required this.id,
    required this.employeeId,
    required this.name,
    this.enrollmentPhotoUrl,
    this.enrolledAt,
    this.faceEmbedding,
  });

  final String id;
  final String employeeId;
  final String name;
  final String? enrollmentPhotoUrl;
  final DateTime? enrolledAt;
  final List<double>? faceEmbedding;

  bool get isEnrolled => enrollmentPhotoUrl != null;

  static Staff fromJson(Map<String, dynamic> json) => Staff(
        id: json['id'] as String,
        employeeId: json['employee_id'] as String,
        name: json['name'] as String,
        enrollmentPhotoUrl: json['enrollment_photo_url'] as String?,
        enrolledAt: json['enrolled_at'] != null ? DateTime.parse(json['enrolled_at'] as String) : null,
        faceEmbedding: (json['face_embedding'] as List<dynamic>?)?.map((e) => (e as num).toDouble()).toList(),
      );
}
