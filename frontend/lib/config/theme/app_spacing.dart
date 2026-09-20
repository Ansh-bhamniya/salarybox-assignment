import 'package:flutter/widgets.dart';

/// Spacing scale (4-pt grid) and the page margins shared by every screen, so
/// content lines up the same way everywhere.
///
/// The side gutter is a fixed 16, the margin Uber's iOS app uses (~4% of a
/// 390pt phone), and it doesn't drift on larger screens. Wide screens are
/// handled separately by `ContentWidth`, which centres content at a readable
/// maximum width.
class AppSpacing {
  AppSpacing._();

  static const double xs = 4;
  static const double s = 8;
  static const double m = 12;
  static const double l = 16;
  static const double xl = 20;
  static const double xxl = 24;

  /// Vertical gap between sections on a screen.
  static const double section = 32;

  /// Left/right margin of screen content.
  static const double gutter = 16;

  /// Left/right inset for centred message screens (empty, error, result).
  static const double messageInset = 24;

  /// Scrollable page content.
  static const EdgeInsets page = EdgeInsets.fromLTRB(gutter, m, gutter, xxl);

  /// Scrollable page content that ends above a floating button.
  static const EdgeInsets pageWithFab = EdgeInsets.fromLTRB(gutter, m, gutter, 96);

  /// A button (or bar) pinned to the bottom of a screen.
  static const EdgeInsets bottomBar = EdgeInsets.fromLTRB(gutter, s, gutter, l);
}
