import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/bloc/auth/auth_cubit.dart';
import 'package:frontend/bloc/auth/auth_state.dart';
import 'package:frontend/config/di/service_locator.dart';
import 'package:frontend/config/router/app_router.dart';
import 'package:frontend/screen/splash/splash_screen.dart';
import 'package:frontend/utils/helpers/onboarding_helper.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeAuthCubit extends Cubit<AuthState> implements AuthCubit {
  _FakeAuthCubit(super.initial);

  @override
  Future<void> login({required String username, required String password}) async {}

  @override
  Future<void> logout() async {}
}

void main() {
  group('SplashScreen', () {
    testWidgets('holds for three seconds, then reports it is finished', (tester) async {
      var finished = 0;
      await tester.pumpWidget(MaterialApp(home: SplashScreen(onFinished: () => finished++)));

      expect(find.bySemanticsLabel('Hey!'), findsOneWidget);

      await tester.pump(const Duration(milliseconds: 2900));
      expect(finished, 0);

      await tester.pump(const Duration(milliseconds: 200));
      expect(finished, 1);
    });

    testWidgets('leaving early never fires the callback', (tester) async {
      var finished = 0;
      await tester.pumpWidget(MaterialApp(home: SplashScreen(onFinished: () => finished++)));
      await tester.pumpWidget(const MaterialApp(home: SizedBox()));

      await tester.pump(const Duration(seconds: 5));
      expect(finished, 0);
    });
  });

  group('app router', () {
    Future<_FakeAuthCubit> pumpApp(WidgetTester tester, AuthState initial) async {
      final cubit = _FakeAuthCubit(initial);
      sl.registerSingleton<AuthCubit>(cubit);
      addTearDown(sl.reset);

      await tester.runAsync(() async {
        SharedPreferences.setMockInitialValues({});
        await SharedPreferences.getInstance();
      });

      await tester.pumpWidget(
        BlocProvider<AuthCubit>.value(
          value: cubit,
          child: MaterialApp.router(routerConfig: buildRouter()),
        ),
      );
      return cubit;
    }

    setUp(() => OnboardingHelper.seen = false);

    testWidgets('starts on the splash and moves on to the intro after three seconds (first run)', (tester) async {
      await pumpApp(tester, const AuthState.unauthenticated());
      await tester.pump();
      expect(find.byType(SplashScreen), findsOneWidget);

      await tester.pump(const Duration(milliseconds: 2900));
      expect(find.byType(SplashScreen), findsOneWidget);

      await tester.pump(const Duration(milliseconds: 200));
      await tester.pumpAndSettle();
      expect(find.byType(SplashScreen), findsNothing);
      expect(find.text('Just look at your phone'), findsOneWidget);
    });

    testWidgets('goes to login when the intro has already been seen', (tester) async {
      OnboardingHelper.seen = true;
      await pumpApp(tester, const AuthState.unauthenticated());
      await tester.pump();

      await tester.pump(SplashScreen.duration);
      await tester.pumpAndSettle();
      expect(find.byType(SplashScreen), findsNothing);
      expect(find.text('Log in'), findsWidgets);
    });

    testWidgets('stays on the splash past three seconds until the session restore finishes', (tester) async {
      OnboardingHelper.seen = true;
      final cubit = await pumpApp(tester, const AuthState.unknown());
      await tester.pump();

      await tester.pump(const Duration(seconds: 6));
      expect(find.byType(SplashScreen), findsOneWidget);

      cubit.emit(const AuthState.unauthenticated());
      await tester.pumpAndSettle();
      expect(find.byType(SplashScreen), findsNothing);
      expect(find.text('Log in'), findsWidgets);
    });
  });
}
