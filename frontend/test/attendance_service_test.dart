import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/services/attendance_service.dart';
import 'package:frontend/utils/http/api_client.dart';
import 'package:frontend/utils/http/api_exception.dart';
import 'helpers/fake_http_adapter.dart';

void main() {
  late FakeHttpAdapter adapter;
  late AttendanceService service;
  late File selfie;

  setUp(() {
    adapter = FakeHttpAdapter()..status = 201;
    final client = ApiClient()..dio.httpClientAdapter = adapter;
    service = AttendanceService(client);
    selfie = File('${Directory.systemTemp.createTempSync('attendance_test').path}/selfie.jpg')
      ..writeAsBytesSync([0xFF, 0xD8, 0xFF, 0xD9]);
  });

  tearDown(() => selfie.parent.deleteSync(recursive: true));

  Future<void> record() => service.record(
        staffId: 'staff-1',
        selfiePath: selfie.path,
        latitude: 28.6139,
        longitude: 77.209,
        matchConfidence: 0.91,
        capturedAt: DateTime(2026, 9, 20, 2, 0),
      );

  test('posts the check-in as multipart to /attendance', () async {
    await record();

    final request = adapter.request;
    expect(request.method, 'POST');
    expect(request.path, '/attendance');

    final form = request.data as FormData;
    final fields = {for (final f in form.fields) f.key: f.value};
    expect(fields['staffId'], 'staff-1');
    expect(fields['latitude'], '28.6139');
    expect(fields['longitude'], '77.209');
    expect(fields['matchConfidence'], '0.91');

    expect(form.files.single.key, 'selfie');
    expect(form.files.single.value.filename, 'attendance.jpg');
  });

  test('sends the capture time as explicit UTC, not a bare local time', () async {
    await record();

    final form = adapter.request.data as FormData;
    final capturedAt = form.fields.firstWhere((f) => f.key == 'capturedAt').value;
    expect(capturedAt.endsWith('Z'), isTrue);
    expect(capturedAt, DateTime(2026, 9, 20, 2, 0).toUtc().toIso8601String());
  });

  test('a backend error comes back as an ApiException carrying its message', () async {
    adapter
      ..status = 403
      ..body = '{"error":"Cannot record attendance for another staff member"}';

    expect(
      record(),
      throwsA(isA<ApiException>()
          .having((e) => e.message, 'message', 'Cannot record attendance for another staff member')
          .having((e) => e.statusCode, 'statusCode', 403)),
    );
  });
}
