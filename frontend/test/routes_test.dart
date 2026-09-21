import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/utils/routes.dart';
import 'package:go_router/go_router.dart';

void main() {
  test('concrete paths fit their patterns', () {
    expect(Routes.staffProfileOf('7'), '/staff/7');
    expect(Routes.enrolOf('7'), '/staff/7/enroll');
    expect(Routes.enrolOf('7', reEnrol: true), '/staff/7/enroll?reenrol=true');
    expect(Routes.staffProfile, '/staff/:id');
    expect(Routes.enrol, '/staff/:id/enroll');
  });

  testWidgets('the admin routes resolve to the right screen, "add" before ":id"', (tester) async {
    final router = GoRouter(
      initialLocation: Routes.staff,
      routes: [
        GoRoute(path: Routes.staff, builder: (_, _) => const Text('LIST')),
        GoRoute(path: Routes.addStaff, builder: (_, _) => const Text('ADD')),
        GoRoute(
          path: Routes.staffProfile,
          builder: (_, state) => Text('PROFILE ${state.pathParameters[Routes.idParam]}'),
        ),
        GoRoute(
          path: Routes.enrol,
          builder: (_, state) => Text('ENROL ${state.pathParameters[Routes.idParam]} ${state.extra}'),
        ),
      ],
    );
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();
    expect(find.text('LIST'), findsOneWidget);

    router.push(Routes.addStaff);
    await tester.pumpAndSettle();
    expect(find.text('ADD'), findsOneWidget);

    router.push(Routes.staffProfileOf('42'));
    await tester.pumpAndSettle();
    expect(find.text('PROFILE 42'), findsOneWidget);

    router.push(Routes.enrolOf('42'), extra: 'Asha');
    await tester.pumpAndSettle();
    expect(find.text('ENROL 42 Asha'), findsOneWidget);
  });
}
