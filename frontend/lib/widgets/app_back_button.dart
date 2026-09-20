import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../config/theme/app_icons.dart';
import '../config/theme/app_spacing.dart';

/// The one back button used on every screen: a round, hairline-bordered
/// button with the Iconsax back arrow. Use it as an AppBar `leading` together
/// with `leadingWidth: AppBackButton.leadingWidth`.
///
/// [onDark] is for the camera screens, whose chrome is always dark.
class AppBackButton extends StatelessWidget {
  const AppBackButton({super.key, this.onDark = false, this.onPressed});

  final bool onDark;

  /// What tapping does. Defaults to going back one screen.
  final VoidCallback? onPressed;

  static const double size = 44;
  static const double leadingWidth = AppSpacing.gutter + size;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final background = onDark ? Colors.black.withValues(alpha: 0.45) : scheme.surfaceContainerLowest;
    final foreground = onDark ? Colors.white : scheme.onSurface;
    final border = onDark ? Colors.white24 : scheme.outlineVariant;

    return Padding(
      padding: const EdgeInsets.only(left: AppSpacing.gutter),
      child: Center(
        child: Tooltip(
          message: 'Back',
          child: Material(
            color: background,
            shape: CircleBorder(side: BorderSide(color: border)),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap:
                  onPressed ??
                  () {
                    if (context.canPop()) context.pop();
                  },
              child: SizedBox(
                width: size,
                height: size,
                child: Icon(AppIcons.back, size: 22, color: foreground),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
