import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import './app_spacing.dart';
import 'app_radius.dart';

/// The app's two themes. Every colour a screen needs lives in these
/// [ColorScheme]s and is read with `Theme.of(context).colorScheme` — screens
/// never pick light/dark colours themselves.
///
/// Light: neutrals plus ONE accent (purple) used in shades. Dark: pure
/// neutrals — black, greys, white — like Uber. In both, hierarchy comes from
/// size, weight and shade, not from extra hues.
///
/// How the scheme is used:
///  * `surface` — the page background
///  * `surfaceContainerLowest` — cards, inputs, sheets (sits above the page)
///  * `onSurface` / `onSurfaceVariant` — primary / secondary text and icons
///  * `outlineVariant` — hairlines and borders
///  * `primary` / `primaryContainer` — the accent, and tinted surfaces of it
///  * `error` — genuine failure states only
///  * `primaryFixedDim` — the accent on the camera, whose chrome is always
///    dark whatever the theme (light purple in the light theme, white in dark)
class AppTheme {
  AppTheme._();

  static ThemeData light() => _build(_lightScheme);

  static ThemeData dark() => _build(_darkScheme);

  /// Big, bold, tightly tracked sans for headline moments (names, times).
  static TextStyle display(BuildContext context, {double size = 40, Color? color}) => GoogleFonts.plusJakartaSans(
        fontSize: size,
        fontWeight: FontWeight.w800,
        height: 1.05,
        letterSpacing: -size * 0.025,
        color: color ?? Theme.of(context).colorScheme.onSurface,
      );

  static const _lightScheme = ColorScheme(
    brightness: Brightness.light,
    primary: Color(0xFF6C4CF1),
    onPrimary: Colors.white,
    primaryContainer: Color(0xFFEDE8FF),
    onPrimaryContainer: Color(0xFF1C1B3A),
    primaryFixed: Color(0xFFDDD3FF),
    primaryFixedDim: Color(0xFFB8A9FF),
    onPrimaryFixed: Color(0xFF1C1B3A),
    onPrimaryFixedVariant: Color(0xFF3B2A99),
    secondary: Color(0xFF6C4CF1),
    onSecondary: Colors.white,
    secondaryContainer: Color(0xFFEDE8FF),
    onSecondaryContainer: Color(0xFF1C1B3A),
    error: Color(0xFFDC2626),
    onError: Colors.white,
    surface: Color(0xFFF6F4FF),
    onSurface: Color(0xFF1C1B3A),
    onSurfaceVariant: Color(0xFF6B6A85),
    surfaceContainerLowest: Colors.white,
    surfaceContainerLow: Colors.white,
    surfaceContainer: Color(0xFFF0EEFA),
    surfaceContainerHigh: Color(0xFFEAE7F7),
    surfaceContainerHighest: Color(0xFFE4E1F3),
    outline: Color(0xFFB9B6D3),
    outlineVariant: Color(0xFFE6E3F5),
    inverseSurface: Color(0xFF1C1B3A),
    onInverseSurface: Colors.white,
    inversePrimary: Color(0xFFB8A9FF),
  );

  /// Dark mode is pure neutral — black, greys and white, like Uber's. There is
  /// no hue: the "accent" is white (a white primary button with black text),
  /// and tinted surfaces are simply a lighter grey.
  static const _darkScheme = ColorScheme(
    brightness: Brightness.dark,
    primary: Colors.white,
    onPrimary: Colors.black,
    primaryContainer: Color(0xFF2B2B2B),
    onPrimaryContainer: Colors.white,
    primaryFixed: Colors.white,
    primaryFixedDim: Colors.white,
    onPrimaryFixed: Colors.black,
    onPrimaryFixedVariant: Color(0xFF3A3A3A),
    secondary: Colors.white,
    onSecondary: Colors.black,
    secondaryContainer: Color(0xFF2B2B2B),
    onSecondaryContainer: Colors.white,
    error: Color(0xFFFF6B6B),
    onError: Color(0xFF3B0A0A),
    surface: Colors.black,
    onSurface: Colors.white,
    onSurfaceVariant: Color(0xFFA6A6A6),
    surfaceContainerLowest: Color(0xFF141414),
    surfaceContainerLow: Color(0xFF141414),
    surfaceContainer: Color(0xFF1C1C1C),
    surfaceContainerHigh: Color(0xFF262626),
    surfaceContainerHighest: Color(0xFF303030),
    outline: Color(0xFF6B6B6B),
    outlineVariant: Color(0xFF2E2E2E),
    inverseSurface: Colors.white,
    onInverseSurface: Colors.black,
    inversePrimary: Colors.black,
  );

  static ThemeData _build(ColorScheme scheme) {
    final isDark = scheme.brightness == Brightness.dark;

    final baseText = ThemeData(brightness: scheme.brightness).textTheme;
    final textTheme = GoogleFonts.plusJakartaSansTextTheme(baseText).apply(
      bodyColor: scheme.onSurface,
      displayColor: scheme.onSurface,
    );

    final controlShape = RoundedRectangleBorder(borderRadius: AppRadius.controlBorder);
    const pillShape = StadiumBorder();

    return ThemeData(
      useMaterial3: true,
      brightness: scheme.brightness,
      colorScheme: scheme,
      textTheme: textTheme,
      scaffoldBackgroundColor: scheme.surface,
      appBarTheme: AppBarTheme(
        centerTitle: false,
        titleSpacing: AppSpacing.gutter,
        backgroundColor: scheme.surface,
        foregroundColor: scheme.onSurface,
        elevation: 0,
        scrolledUnderElevation: 0,
        systemOverlayStyle: isDark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
        titleTextStyle: textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800, color: scheme.onSurface),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: scheme.surfaceContainerLowest,
        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
        border: OutlineInputBorder(borderRadius: AppRadius.controlBorder, borderSide: BorderSide(color: scheme.outlineVariant)),
        enabledBorder: OutlineInputBorder(borderRadius: AppRadius.controlBorder, borderSide: BorderSide(color: scheme.outlineVariant)),
        focusedBorder: OutlineInputBorder(borderRadius: AppRadius.controlBorder, borderSide: BorderSide(color: scheme.primary, width: 2)),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(64, 56),
          shape: controlShape,
          textStyle: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(64, 56),
          shape: controlShape,
          side: BorderSide(color: scheme.outlineVariant),
          textStyle: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
        ),
      ),
      cardTheme: CardThemeData(
        color: scheme.surfaceContainerLowest,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: AppRadius.controlBorder,
          side: BorderSide(color: scheme.outlineVariant),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: scheme.surfaceContainerLowest,
        side: BorderSide(color: scheme.outlineVariant),
        shape: pillShape,
        labelStyle: textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: scheme.surfaceContainerLowest,
        modalBackgroundColor: scheme.surfaceContainerLowest,
        showDragHandle: true,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.sheet))),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: scheme.inverseSurface,
        contentTextStyle: textTheme.bodyMedium?.copyWith(color: scheme.onInverseSurface),
        shape: controlShape,
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(shape: controlShape),
      dividerTheme: DividerThemeData(color: scheme.outlineVariant, thickness: 1, space: 1),
      progressIndicatorTheme: ProgressIndicatorThemeData(color: scheme.primary),
    );
  }
}
