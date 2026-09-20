import 'package:dio/dio.dart';
import '../utils/http/api_client.dart';

/// Everything about attendance: recording a check-in (selfie, location and
/// time) with the backend.
class AttendanceService {
  AttendanceService(this._client);

  final ApiClient _client;

  Future<void> record({
    required String staffId,
    required String selfiePath,
    required double latitude,
    required double longitude,
    required double matchConfidence,
    required DateTime capturedAt,
  }) {
    return runApiCall(() async {
      final formData = FormData.fromMap({
        'staffId': staffId,
        'latitude': latitude.toString(),
        'longitude': longitude.toString(),
        'matchConfidence': matchConfidence.toString(),
        // Explicit UTC ("…Z"): a bare local timestamp would be parsed in the
        // *server's* timezone, shifting the recorded date/time.
        'capturedAt': capturedAt.toUtc().toIso8601String(),
        'selfie': await MultipartFile.fromFile(selfiePath, filename: 'attendance.jpg'),
      });
      await _client.dio.post('/attendance', data: formData);
    });
  }
}
