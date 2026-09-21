import 'dart:convert';
import 'package:dio/dio.dart';
import '../models/attendance_record.dart';
import '../models/face_match_result.dart';
import '../models/staff.dart';
import '../utils/http/api_client.dart';
import '../config/env.dart';

/// Everything about staff members: the list, creating one, deleting one, a single
/// profile, enrolling a face, and a member's attendance history. Talks to the backend
/// and returns models, so screens and cubits never see raw JSON.
class StaffService {
  StaffService(this._client);

  final ApiClient _client;

  Future<List<Staff>> list() {
    return runApiCall(() async {
      final response = await _client.dio.get('/staff');
      return (response.data as List<dynamic>).map((e) => Staff.fromJson(e as Map<String, dynamic>)).toList();
    });
  }

  Future<Staff> create({required String name, required String employeeId}) {
    return runApiCall(() async {
      final response = await _client.dio.post('/staff', data: {'name': name, 'employeeId': employeeId});
      return Staff.fromJson(response.data as Map<String, dynamic>);
    });
  }

  /// Permanently deletes a staff member with their face templates and attendance records.
  Future<void> delete(String id) {
    return runApiCall(() async {
      await _client.dio.delete('/staff/$id');
    });
  }

  Future<Staff> getById(String id) {
    return runApiCall(() async {
      final response = await _client.dio.get('/staff/$id');
      return Staff.fromJson(response.data as Map<String, dynamic>);
    });
  }

  /// Enrols (or re-enrols) a person from several captures at once. Throws an
  /// [ApiException] with code `duplicate_face` if the face already belongs to
  /// another staff member, unless [allowDuplicate] is set (which needs a [reason]).
  Future<Staff> enroll({
    required String id,
    required List<FaceSample> shots,
    String? reason,
    bool allowDuplicate = false,
  }) {
    return runApiCall(() async {
      final formData = FormData.fromMap({
        'embeddings': jsonEncode([for (final shot in shots) shot.embedding]),
        'modelVersion': Env.faceModelVersion,
        'reason': ?reason,
        if (allowDuplicate) 'allowDuplicate': 'true',
        'photos': [
          for (var i = 0; i < shots.length; i++)
            await MultipartFile.fromFile(shots[i].imagePath, filename: 'enrollment_$i.jpg'),
        ],
      });
      final response = await _client.dio.post('/staff/$id/enroll', data: formData);
      return Staff.fromJson(response.data as Map<String, dynamic>);
    });
  }

  Future<List<AttendanceRecord>> attendanceHistory(String id) {
    return runApiCall(() async {
      final response = await _client.dio.get('/staff/$id/attendance');
      return (response.data as List<dynamic>).map((e) => AttendanceRecord.fromJson(e as Map<String, dynamic>)).toList();
    });
  }
}
