import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

/// Fills the whole screen with the preview, cropping the overflow instead of
/// letterboxing it (a raw [CameraPreview] keeps the sensor's aspect ratio and
/// leaves black bars). Assumes the screen is locked to portrait.
class CoverCameraPreview extends StatelessWidget {
  const CoverCameraPreview({super.key, required this.controller});

  final CameraController controller;

  @override
  Widget build(BuildContext context) {
    final previewSize = controller.value.previewSize;
    if (previewSize == null) return const SizedBox.shrink();

    // previewSize is reported in sensor (landscape) terms; the UI is locked
    // to portrait, so the short side is the width.
    final width = previewSize.width < previewSize.height ? previewSize.width : previewSize.height;
    final height = previewSize.width < previewSize.height ? previewSize.height : previewSize.width;

    return ClipRect(
      child: FittedBox(
        fit: BoxFit.cover,
        child: SizedBox(width: width, height: height, child: CameraPreview(controller)),
      ),
    );
  }
}
