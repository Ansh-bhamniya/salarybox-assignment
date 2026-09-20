import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Wraps [CameraController] for the one thing every screen in this app
/// needs from the camera: open the front lens, take a single selfie, clean
/// up. Both the face-enrolment screen and the mark-attendance screen use
/// this instead of each managing their own [CameraController] lifecycle.
class CameraCaptureController {
  CameraController? _controller;

  CameraController? get controller => _controller;

  bool get isReady => _controller?.value.isInitialized ?? false;

  Future<void> initialize() async {
    // "Try again" re-enters here while the previous controller may still be
    // alive; release it first so we never hold two camera sessions.
    await dispose();

    final cameras = await availableCameras();
    final frontCamera = cameras.firstWhere(
      (camera) => camera.lensDirection == CameraLensDirection.front,
      orElse: () => cameras.first,
    );

    final controller = CameraController(
      frontCamera,
      ResolutionPreset.high,
      enableAudio: false,
      // Formats ML Kit can read straight from the live frame stream.
      imageFormatGroup: defaultTargetPlatform == TargetPlatform.iOS ? ImageFormatGroup.bgra8888 : ImageFormatGroup.nv21,
    );
    await controller.initialize();
    try {
      // Keep photos upright regardless of how the phone is held, so face
      // detection never sees a sideways selfie.
      await controller.lockCaptureOrientation(DeviceOrientation.portraitUp);
    } catch (_) {
      // Not fatal: the photo is re-oriented from EXIF before detection anyway.
    }
    _controller = controller;
  }

  /// Streams live preview frames (used for real-time framing guidance).
  /// Best-effort: if the stream can't start, capture still works.
  Future<void> startImageStream(void Function(CameraImage image) onImage) async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized || controller.value.isStreamingImages) {
      return;
    }
    try {
      await controller.startImageStream(onImage);
    } catch (_) {}
  }

  Future<void> stopImageStream() async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized || !controller.value.isStreamingImages) {
      return;
    }
    try {
      await controller.stopImageStream();
    } catch (_) {}
  }

  Future<XFile> capture() async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) {
      throw StateError('Camera not initialized');
    }
    await stopImageStream();
    return controller.takePicture();
  }

  Future<void> dispose() async {
    final controller = _controller;
    _controller = null;
    await controller?.dispose();
  }
}
