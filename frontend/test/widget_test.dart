import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/widgets/primary_button.dart';

void main() {
  testWidgets('PrimaryButton shows its label and responds to taps', (tester) async {
    var tapped = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PrimaryButton(label: 'Log in', onPressed: () => tapped = true),
        ),
      ),
    );

    expect(find.text('Log in'), findsOneWidget);
    await tester.tap(find.byType(PrimaryButton));
    expect(tapped, isTrue);
  });

  testWidgets('PrimaryButton shows a spinner instead of its label while loading', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PrimaryButton(label: 'Log in', loading: true, onPressed: () {}),
        ),
      ),
    );

    expect(find.text('Log in'), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });
}
