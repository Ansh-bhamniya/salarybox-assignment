import 'package:flutter/widgets.dart';

/// Corner radii, defined once so the staff and admin screens are identical.
/// Change a value here and every card, button, input and tile follows.
class AppRadius {
  AppRadius._();

  /// Cards, buttons, text fields, the floating button, snackbars.
  static const double control = 12;

  /// Small tiles that sit inside a card (date bubbles, photo thumbnails).
  static const double tile = 8;

  /// Top corners of a bottom sheet.
  static const double sheet = 16;

  /// Fully round — only for small chips and pills.
  static const double pill = 999;

  static final BorderRadius controlBorder = BorderRadius.circular(control);
  static final BorderRadius tileBorder = BorderRadius.circular(tile);
  static final BorderRadius pillBorder = BorderRadius.circular(pill);
}
