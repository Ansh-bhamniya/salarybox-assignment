import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/config/theme/app_theme.dart';
import 'package:frontend/widgets/camera_status_view.dart';

Widget _view(ThemeData theme, {required bool onDark}) => MaterialApp(
  theme: theme,
  home: Scaffold(
    body: CameraStatusView(
      icon: Icons.check,
      color: Colors.green,
      title: 'Attendance recorded',
      message: 'Saved.',
      primaryLabel: 'Done',
      onPrimary: () {},
      onDark: onDark,
    ),
  ),
);

Color? _titleColor(WidgetTester tester) => tester.widget<Text>(find.text('Attendance recorded')).style?.color;

void main() {
  testWidgets('a result screen follows the light theme: dark text', (tester) async {
    await tester.pumpWidget(_view(AppTheme.light(), onDark: false));
    expect(_titleColor(tester), AppTheme.light().colorScheme.onSurface);
  });

  testWidgets('a result screen follows the dark theme: light text', (tester) async {
    await tester.pumpWidget(_view(AppTheme.dark(), onDark: false));
    expect(_titleColor(tester), AppTheme.dark().colorScheme.onSurface);
  });

  testWidgets('by default it stays white for the dark camera screens, in either theme', (tester) async {
    await tester.pumpWidget(_view(AppTheme.light(), onDark: true));
    expect(_titleColor(tester), Colors.white);
  });
}
