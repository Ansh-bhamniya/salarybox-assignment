import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/screen/onboarding/onboarding_screen.dart';
import 'package:frontend/utils/helpers/onboarding_helper.dart';
import 'package:frontend/utils/routes.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> _prefs([Map<String, Object> initial = const {}]) async {
  SharedPreferences.setMockInitialValues(initial);
  await SharedPreferences.getInstance();
}

GoRouter _router() => GoRouter(
  routes: [
    GoRoute(path: '/', builder: (context, state) => const OnboardingScreen()),
    GoRoute(
      path: Routes.login,
      builder: (context, state) => const Scaffold(body: Center(child: Text('LOGIN'))),
    ),
  ],
);

void main() {
  group('OnboardingHelper', () {
    test('the intro has not been seen on first launch', () async {
      await _prefs();
      OnboardingHelper.seen = true; // prove load() overwrites it
      await OnboardingHelper.load();
      expect(OnboardingHelper.seen, isFalse);
    });

    test('marking it seen is remembered across restarts', () async {
      await _prefs();
      await OnboardingHelper.markSeen();
      expect(OnboardingHelper.seen, isTrue);

      OnboardingHelper.seen = false; // a fresh launch
      await OnboardingHelper.load();
      expect(OnboardingHelper.seen, isTrue);
    });
  });

  group('OnboardingScreen', () {
    setUp(() => OnboardingHelper.seen = false);

    testWidgets('walks through three pages (button and swipe), then continues to login and remembers it', (
      tester,
    ) async {
      await tester.runAsync(_prefs);
      await tester.pumpWidget(MaterialApp.router(routerConfig: _router()));
      await tester.pumpAndSettle();

      expect(find.text('Just look at your phone'), findsOneWidget);
      expect(find.text('Next'), findsOneWidget);

      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();
      expect(find.text("We make sure it's really you"), findsOneWidget);

      await tester.fling(find.byType(PageView), const Offset(-400, 0), 1000);
      await tester.pumpAndSettle();
      expect(find.text('Marked. Go start your day.'), findsOneWidget);
      expect(find.text('Get started'), findsOneWidget);

      await tester.tap(find.text('Get started'));
      await tester.pumpAndSettle();
      expect(find.text('LOGIN'), findsOneWidget);
      expect(OnboardingHelper.seen, isTrue);
    });

    testWidgets('Skip is shown on the first pages and hidden on the last', (tester) async {
      await tester.runAsync(_prefs);
      await tester.pumpWidget(MaterialApp.router(routerConfig: _router()));
      await tester.pumpAndSettle();

      double skipOpacity() => tester
          .widget<AnimatedOpacity>(find.ancestor(of: find.text('Skip'), matching: find.byType(AnimatedOpacity)))
          .opacity;

      expect(skipOpacity(), 1);

      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();
      expect(find.text('Get started'), findsOneWidget);
      expect(skipOpacity(), 0);
    });

    testWidgets('Skip jumps straight to login and remembers it', (tester) async {
      await tester.runAsync(_prefs);
      await tester.pumpWidget(MaterialApp.router(routerConfig: _router()));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Skip'));
      await tester.pumpAndSettle();

      expect(find.text('LOGIN'), findsOneWidget);
      expect(OnboardingHelper.seen, isTrue);
    });
  });
}
