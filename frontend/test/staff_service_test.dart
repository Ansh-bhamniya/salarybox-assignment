import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/services/staff_service.dart';
import 'package:frontend/utils/http/api_client.dart';
import 'package:frontend/utils/http/api_exception.dart';
import 'helpers/fake_http_adapter.dart';

const _enrolled = '''
{"id":"1","employee_id":"E-1","name":"Sam Rao","enrollment_photo_url":"https://x/p.jpg",
 "enrolled_at":"2026-09-19T15:35:11.416+00:00","face_embedding":[0.1,0.2]}''';
const _notEnrolled = '{"id":"2","employee_id":"E-2","name":"Asha Nair","enrollment_photo_url":null}';

void main() {
  late FakeHttpAdapter adapter;
  late StaffService service;

  setUp(() {
    adapter = FakeHttpAdapter();
    service = StaffService(ApiClient()..dio.httpClientAdapter = adapter);
  });

  test('list() GETs /staff and returns Staff models', () async {
    adapter.body = '[$_enrolled,$_notEnrolled]';

    final staff = await service.list();

    expect(adapter.request.method, 'GET');
    expect(adapter.request.path, '/staff');
    expect(staff.map((s) => s.name), ['Sam Rao', 'Asha Nair']);
    expect(staff.map((s) => s.isEnrolled), [true, false]);
    expect(staff.first.faceEmbedding, [0.1, 0.2]);
  });

  test('create() POSTs the name and employee id and returns the new staff member', () async {
    adapter
      ..status = 201
      ..body = _notEnrolled;

    final staff = await service.create(name: 'Asha Nair', employeeId: 'E-2');

    expect(adapter.request.path, '/staff');
    expect(adapter.request.data, {'name': 'Asha Nair', 'employeeId': 'E-2'});
    expect(staff.employeeId, 'E-2');
  });

  test('getById() GETs one staff member', () async {
    adapter.body = _enrolled;

    final staff = await service.getById('1');

    expect(adapter.request.path, '/staff/1');
    expect(staff.id, '1');
  });

  test('enroll() uploads the photo and the embedding as multipart', () async {
    adapter.body = _enrolled;
    final dir = Directory.systemTemp.createTempSync('staff_test');
    addTearDown(() => dir.deleteSync(recursive: true));
    final photo = File('${dir.path}/face.jpg')..writeAsBytesSync([0xFF, 0xD8, 0xFF, 0xD9]);

    final staff = await service.enroll(id: '1', photoPath: photo.path, embedding: [0.5, 0.25]);

    expect(adapter.request.path, '/staff/1/enroll');
    final form = adapter.request.data as FormData;
    expect(form.fields.firstWhere((f) => f.key == 'embedding').value, '[0.5,0.25]');
    expect(form.fields.firstWhere((f) => f.key == 'modelVersion').value, 'mobilefacenet-192-v1');
    expect(form.files.single.key, 'photo');
    expect(form.files.single.value.filename, 'enrollment.jpg');
    expect(staff.isEnrolled, isTrue);
  });

  test('attendanceHistory() maps the records', () async {
    adapter.body = '''[
      {"id":"a1","date":"2026-09-19","time":"20:30:00","selfie_url":"https://x/s.jpg",
       "latitude":28.6139,"longitude":77.209,"match_confidence":0.91}
    ]''';

    final records = await service.attendanceHistory('1');

    expect(adapter.request.path, '/staff/1/attendance');
    expect(records.single.id, 'a1');
    expect(records.single.latitude, 28.6139);
    expect(records.single.matchConfidence, 0.91);
    // Stored as UTC; the model exposes it in the viewer's local time.
    expect(records.single.timestamp.toUtc(), DateTime.utc(2026, 9, 19, 20, 30));
  });

  test('a backend error is an ApiException with the backend message', () async {
    adapter
      ..status = 404
      ..body = '{"error":"Staff not found"}';

    await expectLater(
      service.getById('nope'),
      throwsA(isA<ApiException>().having((e) => e.message, 'message', 'Staff not found')),
    );
  });
}
