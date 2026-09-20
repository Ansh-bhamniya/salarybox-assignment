import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/bloc/auth/auth_cubit.dart';
import 'package:frontend/bloc/auth/auth_state.dart';
import 'package:frontend/screen/login/login_screen.dart';
import 'package:frontend/screen/onboarding/onboarding_screen.dart';
import 'package:frontend/utils/helpers/onboarding_helper.dart';
import 'package:frontend/utils/routes.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeAuthCubit extends Cubit<AuthState> implements AuthCubit {
  _FakeAuthCubit() : super(const AuthState.unauthenticated());

  @override
  Future<void> login({required String username, required String password}) async {}

  @override
  Future<void> logout() async {}
}

Widget _app(String initialLocation) {
  final cubit = _FakeAuthCubit();
  return MaterialApp.router(
    routerConfig: GoRouter(
      initialLocation: initialLocation,
      routes: [
        GoRoute(path: Routes.onboarding, builder: (context, state) => const OnboardingScreen()),
        GoRoute(
          path: Routes.login,
          builder: (context, state) => BlocProvider<AuthCubit>.value(value: cubit, child: const LoginScreen()),
        ),
      ],
    ),
  );
}

void main() {
  setUp(() => OnboardingHelper.seen = false);

  Future<void> primePrefs(WidgetTester tester) => tester.runAsync(() async {
    SharedPreferences.setMockInitialValues({});
    await SharedPreferences.getInstance();
  });

  testWidgets('from the intro, login slides in and its back button returns to the intro', (tester) async {
    await primePrefs(tester);
    await tester.pumpWidget(_app(Routes.onboarding));
    await tester.pumpAndSettle();
    expect(find.text('Just look at your phone'), findsOneWidget);

    await tester.tap(find.text('Skip'));
    await tester.pumpAndSettle();
    expect(find.text('Log in'), findsOneWidget);
    expect(find.byTooltip('Back'), findsOneWidget);

    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();
    expect(find.text('Just look at your phone'), findsOneWidget);
    expect(find.text('Log in'), findsNothing);
  });

  testWidgets('login opened directly: back opens the intro', (tester) async {
    await primePrefs(tester);
    await tester.pumpWidget(_app(Routes.login));
    await tester.pumpAndSettle();
    expect(find.text('Log in'), findsOneWidget);

    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();

    expect(find.text('Just look at your phone'), findsOneWidget);
  });

  testWidgets('the intro can be walked through again after going back', (tester) async {
    await primePrefs(tester);
    await tester.pumpWidget(_app(Routes.onboarding));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Skip'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
    expect(find.text("We make sure it's really you"), findsOneWidget);
  });
}
