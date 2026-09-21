import 'package:flutter/material.dart';
import '../config/theme/app_spacing.dart';

/// Full-screen message: a tinted icon, a title, a short explanation and one or
/// two actions. Used for camera errors, "face didn't match" and "attendance
/// recorded". It is white-on-black by default, for the dark camera screens; with
/// [onDark] false it follows the app's light or dark theme instead (the screens
/// that show a result once the camera is gone).
class CameraStatusView extends StatelessWidget {
  const CameraStatusView({
    super.key,
    required this.icon,
    required this.color,
    required this.title,
    required this.message,
    required this.primaryLabel,
    required this.onPrimary,
    this.secondaryLabel,
    this.onSecondary,
    this.onDark = true,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String message;
  final String primaryLabel;
  final VoidCallback onPrimary;
  final String? secondaryLabel;
  final VoidCallback? onSecondary;
  final bool onDark;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final titleColor = onDark ? Colors.white : scheme.onSurface;
    final messageColor = onDark ? Colors.white70 : scheme.onSurfaceVariant;

    return SafeArea(
      child: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.messageInset),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 96,
                  height: 96,
                  decoration: BoxDecoration(shape: BoxShape.circle, color: color.withValues(alpha: 0.18)),
                  child: Icon(icon, size: 48, color: color),
                ),
              ),
              const SizedBox(height: 24),
              Text(
                title,
                textAlign: TextAlign.center,
                style: Theme.of(
                  context,
                ).textTheme.headlineSmall?.copyWith(color: titleColor, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              Text(
                message,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: messageColor),
              ),
              const SizedBox(height: 32),
              FilledButton(
                onPressed: onPrimary,
                style: onDark
                    ? FilledButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: Colors.black,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                      )
                    : null,
                child: Text(primaryLabel),
              ),
              if (secondaryLabel != null) ...[
                const SizedBox(height: 12),
                OutlinedButton(
                  onPressed: onSecondary,
                  style: onDark
                      ? OutlinedButton.styleFrom(
                          foregroundColor: Colors.white,
                          side: const BorderSide(color: Colors.white54),
                          padding: const EdgeInsets.symmetric(vertical: 16),
                        )
                      : null,
                  child: Text(secondaryLabel!),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
