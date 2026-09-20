import 'dart:convert';
import 'package:dio/dio.dart';
import '../models/attendance_record.dart';
import '../models/staff.dart';
import '../utils/http/api_client.dart';

/// Everything about staff members: the list, creating one, a single profile,
/// enrolling a face, and a member's attendance history. Talks to the backend
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

  Future<Staff> getById(String id) {
    return runApiCall(() async {
      final response = await _client.dio.get('/staff/$id');
      return Staff.fromJson(response.data as Map<String, dynamic>);
    });
  }

  Future<Staff> enroll({
    required String id,
    required String photoPath,
    required List<double> embedding,
  }) {
    return runApiCall(() async {
      final formData = FormData.fromMap({
        'embedding': jsonEncode(embedding),
        'photo': await MultipartFile.fromFile(photoPath, filename: 'enrollment.jpg'),
      });
      final response = await _client.dio.post('/staff/$id/enroll', data: formData);
      return Staff.fromJson(response.data as Map<String, dynamic>);
    });
  }

  Future<List<AttendanceRecord>> attendanceHistory(String id) {
    return runApiCall(() async {
      final response = await _client.dio.get('/staff/$id/attendance');
      return (response.data as List<dynamic>)
          .map((e) => AttendanceRecord.fromJson(e as Map<String, dynamic>))
          .toList();
    });
  }
}
