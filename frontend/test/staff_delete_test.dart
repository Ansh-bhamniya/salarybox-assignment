import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/bloc/staff_profile/staff_profile_cubit.dart';
import 'package:frontend/screen/staff_profile/delete_staff_dialog.dart';
import 'package:frontend/services/staff_service.dart';
import 'package:frontend/utils/http/api_client.dart';
import 'package:frontend/utils/http/api_exception.dart';
import 'helpers/fake_http_adapter.dart';

const _staff = '{"id":"S1","employee_id":"E-1","name":"Sam Rao","enrollment_photo_url":null,"face_templates":[]}';

/// Answers each kind of request differently: the profile and its attendance list are read
/// when the cubit starts, the delete is what the test is about.
class _Routed implements HttpClientAdapter {
  final requests = <RequestOptions>[];
  int deleteStatus = 204;
  String deleteBody = '';

  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? requestStream, Future<void>? cancel) async {
    requests.add(options);
    final String body;
    var status = 200;
    if (options.method == 'DELETE') {
      status = deleteStatus;
      body = deleteBody;
    } else {
      body = options.path.endsWith('/attendance') ? '[]' : _staff;
    }
    return ResponseBody.fromString(
      body,
      status,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  late FakeHttpAdapter adapter;
  late StaffService service;

  setUp(() {
    adapter = FakeHttpAdapter();
    service = StaffService(ApiClient()..dio.httpClientAdapter = adapter);
  });

  group('StaffService.delete', () {
    test('sends DELETE /staff/:id', () async {
      adapter.status = 204;
      adapter.body = '';

      await service.delete('S1');

      expect(adapter.request.method, 'DELETE');
      expect(adapter.request.path, '/staff/S1');
    });

    test('a refusal from the server becomes an ApiException with its message', () async {
      adapter
        ..status = 404
        ..body = '{"error":"Staff not found"}';

      expect(service.delete('S1'), throwsA(isA<ApiException>().having((e) => e.message, 'message', 'Staff not found')));
    });
  });

  group('StaffProfileCubit.delete', () {
    late _Routed routed;

    Future<StaffProfileCubit> loaded() async {
      routed = _Routed();
      final cubit = StaffProfileCubit(StaffService(ApiClient()..dio.httpClientAdapter = routed), 'S1');
      addTearDown(cubit.close);
      await pumpEventQueue();
      expect(cubit.state.staff?.id, 'S1', reason: 'setup: the profile should have loaded');
      return cubit;
    }

    List<String> deletes() => routed.requests.where((r) => r.method == 'DELETE').map((r) => r.path).toList();

    test('returns null once the staff member is deleted, and asked the server to do it', () async {
      final cubit = await loaded();

      final problem = await cubit.delete();

      expect(problem, isNull);
      expect(deletes(), ['/staff/S1']);
    });

    test('says so while it is deleting', () async {
      final cubit = await loaded();
      final states = <bool>[];
      final subscription = cubit.stream.listen((state) => states.add(state.deleting));
      addTearDown(subscription.cancel);

      await cubit.delete();
      await pumpEventQueue();

      expect(states.first, isTrue);
    });

    test('a failure is handed back as a message, and the profile stays as it was', () async {
      final cubit = await loaded();
      final before = cubit.state;
      routed
        ..deleteStatus = 500
        ..deleteBody = '{"error":"Could not delete"}';

      final problem = await cubit.delete();

      expect(problem, 'Could not delete');
      expect(cubit.state.deleting, isFalse);
      expect(cubit.state.status, before.status);
      expect(cubit.state.staff?.id, before.staff?.id);
    });

    test('asking twice at once deletes once', () async {
      final cubit = await loaded();

      await Future.wait([cubit.delete(), cubit.delete()]);

      expect(deletes().length, 1);
    });
  });

  group('the confirmation dialog', () {
    Future<bool?> ask(WidgetTester tester, {required String tap, int records = 3}) async {
      bool? result;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () async =>
                    result = await confirmDeleteStaff(context, name: 'Sam Rao', attendanceRecords: records),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.tap(find.text(tap));
      await tester.pumpAndSettle();
      return result;
    }

    testWidgets('names the person and says what goes with them', (tester) async {
      await ask(tester, tap: 'Cancel', records: 3);
      // (dialog already closed by Cancel; open it again to read it)
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(find.text('Delete Sam Rao?'), findsOneWidget);
      expect(find.textContaining('3 attendance records'), findsOneWidget);
      expect(find.textContaining('cannot be undone'), findsOneWidget);
    });

    testWidgets('one record reads in the singular', (tester) async {
      await ask(tester, tap: 'Cancel', records: 1);
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(find.textContaining('1 attendance record,'), findsOneWidget);
    });

    testWidgets('Delete confirms', (tester) async {
      expect(await ask(tester, tap: 'Delete'), isTrue);
    });

    testWidgets('Cancel does not', (tester) async {
      expect(await ask(tester, tap: 'Cancel'), isFalse);
    });

    testWidgets('tapping away does not either', (tester) async {
      bool? result;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () async => result = await confirmDeleteStaff(context, name: 'Sam', attendanceRecords: 0),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.tapAt(const Offset(4, 4));
      await tester.pumpAndSettle();

      expect(result, isFalse);
    });
  });
}
