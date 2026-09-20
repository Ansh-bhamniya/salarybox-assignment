import 'package:flutter/material.dart';

/// Full-screen scrim + spinner shown while a screen is doing something the
/// user has to wait for (uploading a selfie, running inference). Stacked on
/// top of the screen's normal content rather than replacing it, so the
/// camera preview or form underneath doesn't jump when it appears.
class LoadingOverlay extends StatelessWidget {
  const LoadingOverlay({super.key, required this.visible, this.message});

  final bool visible;
  final String? message;

  @override
  Widget build(BuildContext context) {
    if (!visible) return const SizedBox.shrink();

    return Positioned.fill(
      child: ColoredBox(
        color: Colors.black54,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(color: Colors.white),
              if (message != null) ...[
                const SizedBox(height: 16),
                Text(message!, style: const TextStyle(color: Colors.white)),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
