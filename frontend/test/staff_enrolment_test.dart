import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/config/di/service_locator.dart';
import 'package:frontend/bloc/staff_list/staff_list_cubit.dart';
import 'package:frontend/models/duplicate_match.dart';
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

  group('Staff face templates', () {
    Staff parse(Map<String, dynamic> extra) =>
        Staff.fromJson({'id': '1', 'employee_id': 'E-1', 'name': 'Sam', ...extra});

    test('reads every active template, frontal first', () {
      final staff = parse({
        'enrolled': true,
        'face_templates': [
          {
            'id': 'a',
            'model_version': 'm1',
            'embedding': [1, 0],
          },
          {
            'id': 'b',
            'model_version': 'm1',
            'embedding': [0.5, 0.5],
          },
        ],
      });

      expect(staff.faceTemplates.length, 2);
      expect(staff.faceEmbedding, [1.0, 0.0]);
    });

    test('only templates from the asked-for model version are comparable', () {
      final staff = parse({
        'face_templates': [
          {
            'id': 'a',
            'model_version': 'old-model',
            'embedding': [1, 0],
          },
          {
            'id': 'b',
            'model_version': 'm1',
            'embedding': [0, 1],
          },
          {
            'id': 'c',
            'model_version': 'm1',
            'embedding': [0.5, 0.5],
          },
        ],
      });

      expect(staff.embeddingsFor('m1'), [
        [0.0, 1.0],
        [0.5, 0.5],
      ]);
      expect(staff.embeddingsFor('missing'), isEmpty);
    });

    test('a backend that only sends one embedding is treated as one template of the current model', () {
      final staff = parse({
        'face_embedding': [0.1, 0.2],
      });

      expect(staff.faceTemplates.single.modelVersion, FaceTemplate.legacyModelVersion);
      expect(staff.embeddingsFor(FaceTemplate.legacyModelVersion), [
        [0.1, 0.2],
      ]);
    });

    test('list responses carry no templates', () {
      final staff = parse({'enrolled': true});

      expect(staff.faceTemplates, isEmpty);
      expect(staff.faceEmbedding, isNull);
    });
  });

  group('DuplicateMatch.listFrom', () {
    test('reads the matches out of the error details', () {
      final matches = DuplicateMatch.listFrom({
        'matches': [
          {'staffId': '9', 'employeeId': 'E-9', 'name': 'Ravi', 'similarity': 0.83},
        ],
      });

      expect(matches.single.name, 'Ravi');
      expect(matches.single.similarity, 0.83);
    });

    test('anything unexpected yields no matches instead of throwing', () {
      expect(DuplicateMatch.listFrom(null), isEmpty);
      expect(DuplicateMatch.listFrom('nope'), isEmpty);
      expect(DuplicateMatch.listFrom({'matches': 'nope'}), isEmpty);
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
