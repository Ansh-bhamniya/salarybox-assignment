import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/config/di/service_locator.dart';
import 'package:frontend/bloc/staff_list/staff_list_cubit.dart';
import 'package:frontend/models/staff.dart';
import 'package:frontend/screen/staff_list/staff_list_screen.dart';
import 'package:frontend/services/staff_service.dart';
import 'package:frontend/utils/http/api_client.dart';
import 'helpers/fake_http_adapter.dart';

const _sam = '{"id":"1","employee_id":"E-1","name":"Sam Rao","enrolled":true}';
const _asha = '{"id":"2","employee_id":"E-2","name":"Asha Nair","enrolled":false}';
const _lee = '{"id":"3","employee_id":"E-3","name":"Lee Park","enrolled":false}';

void main() {
  group('Staff.isEnrolled', () {
    Staff parse(Map<String, dynamic> extra) =>
        Staff.fromJson({'id': '1', 'employee_id': 'E-1', 'name': 'Sam', ...extra});

    test('follows the backend flag', () {
      expect(parse({'enrolled': true}).isEnrolled, isTrue);
      expect(parse({'enrolled': false}).isEnrolled, isFalse);
    });

    test('a photo alone does not count when the backend says there is no active face', () {
      // e.g. an old enrolment whose face template can never match the current model.
      expect(parse({'enrollment_photo_url': 'https://x/p.jpg', 'enrolled': false}).isEnrolled, isFalse);
    });

    test('falls back to the photo for a backend that predates the flag', () {
      expect(parse({'enrollment_photo_url': 'https://x/p.jpg'}).isEnrolled, isTrue);
      expect(parse({}).isEnrolled, isFalse);
    });
  });

  group('staff list "Not enrolled" filter', () {
    late FakeHttpAdapter adapter;

    setUp(() {
      adapter = FakeHttpAdapter();
      sl.registerFactory<StaffListCubit>(
        () => StaffListCubit(StaffService(ApiClient()..dio.httpClientAdapter = adapter)),
      );
    });
    tearDown(sl.reset);

    Future<void> pumpList(WidgetTester tester) async {
      await tester.pumpWidget(const MaterialApp(home: StaffListScreen()));
      await tester.pumpAndSettle();
    }

    testWidgets('narrows the list to staff who still need enrolment, and back', (tester) async {
      adapter.body = '[$_sam,$_asha,$_lee]';
      await pumpList(tester);

      expect(find.text('3 staff • 2 need face enrolment'), findsOneWidget);
      expect(find.text('Sam Rao'), findsOneWidget);
      expect(find.text('Asha Nair'), findsOneWidget);

      await tester.tap(find.widgetWithText(FilterChip, 'Not enrolled'));
      await tester.pumpAndSettle();
      expect(find.text('Sam Rao'), findsNothing);
      expect(find.text('Asha Nair'), findsOneWidget);
      expect(find.text('Lee Park'), findsOneWidget);

      await tester.tap(find.widgetWithText(FilterChip, 'Not enrolled'));
      await tester.pumpAndSettle();
      expect(find.text('Sam Rao'), findsOneWidget);
    });

    testWidgets('is not offered when everyone is enrolled', (tester) async {
      adapter.body = '[$_sam]';
      await pumpList(tester);

      expect(find.text('1 staff • all enrolled'), findsOneWidget);
      expect(find.byType(FilterChip), findsNothing);
    });
  });
}
