import 'dart:convert';
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
    Map<String, Object?>? liveness,
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
        // What the head-turn check saw (which turns, how long, how far), kept for the audit trail.
        'liveness': ?(liveness == null ? null : jsonEncode(liveness)),
        'selfie': await MultipartFile.fromFile(selfiePath, filename: 'attendance.jpg'),
      });
      await _client.dio.post('/attendance', data: formData);
    });
  }

  /// Tells the backend a check did not pass, so failures can be reviewed:
  /// [outcome] is `liveness_failed` (the head-turn check) or `no_match` (the
  /// face was not the enrolled person's), [reason] a short word such as
  /// `timeout`. Best effort; callers should not let it change what the person sees.
  Future<void> reportFailedAttempt({required String outcome, String? reason}) {
    return runApiCall(() async {
      await _client.dio.post('/attendance/attempts', data: {'outcome': outcome, 'reason': ?reason});
    });
  }
}
