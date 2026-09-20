import 'dart:ui';
import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';

/// What the live preview should tell the user right now.
enum FaceGuidance {
  searching('Position your face inside the oval'),
  multipleFaces('Only one person should be in frame'),
  tooFar('Move a little closer'),
  tooClose('Move back a little'),
  offCenter('Center your face in the oval'),
  lookStraight('Look straight at the camera'),
  good('Perfect — hold still');

  const FaceGuidance(this.message);
  final String message;
}

/// Runs lightweight ML Kit face detection on the live camera frames and
/// publishes [guidance] so the UI can coach the user into a good selfie
/// *before* they press the shutter. Purely advisory: it never blocks
/// capture, so a device where the frame stream misbehaves still works.
class FaceGuidanceAnalyzer {
  FaceGuidanceAnalyzer({required this.sensorOrientation});

  final int sensorOrientation;

  final ValueNotifier<FaceGuidance> guidance = ValueNotifier(FaceGuidance.searching);

  final FaceDetector _detector = FaceDetector(
    options: FaceDetectorOptions(performanceMode: FaceDetectorMode.fast, minFaceSize: 0.15),
  );

  static const _minInterval = Duration(milliseconds: 250);

  bool _busy = false;
  bool _closed = false;
  DateTime _lastRun = DateTime.fromMillisecondsSinceEpoch(0);

  Future<void> onFrame(CameraImage image) async {
    if (_busy || _closed) return;
    final now = DateTime.now();
    if (now.difference(_lastRun) < _minInterval) return;
    _busy = true;
    _lastRun = now;

    try {
      final input = _toInputImage(image);
      if (input == null) return;
      final faces = await _detector.processImage(input);
      if (_closed) return;
      guidance.value = _evaluate(faces, image);
    } catch (_) {
      // A single bad frame is not worth surfacing.
    } finally {
      _busy = false;
    }
  }

  InputImage? _toInputImage(CameraImage image) {
    final rotation = InputImageRotationValue.fromRawValue(sensorOrientation);
    final format = InputImageFormatValue.fromRawValue(image.format.raw);
    if (rotation == null || format == null) return null;
    if (format != InputImageFormat.nv21 && format != InputImageFormat.bgra8888) return null;
    if (image.planes.length != 1) return null;

    final plane = image.planes.first;
    return InputImage.fromBytes(
      bytes: plane.bytes,
      metadata: InputImageMetadata(
        size: Size(image.width.toDouble(), image.height.toDouble()),
        rotation: rotation,
        format: format,
        bytesPerRow: plane.bytesPerRow,
      ),
    );
  }

  FaceGuidance _evaluate(List<Face> faces, CameraImage image) {
    if (faces.isEmpty) return FaceGuidance.searching;
    if (faces.length > 1) return FaceGuidance.multipleFaces;

    // ML Kit reports boxes in the upright (rotated) frame, so for a
    // sideways sensor the frame's width/height swap.
    final sideways = sensorOrientation == 90 || sensorOrientation == 270;
    final frameWidth = (sideways ? image.height : image.width).toDouble();
    final frameHeight = (sideways ? image.width : image.height).toDouble();

    final face = faces.single;
    final box = face.boundingBox;
    final widthRatio = box.width / frameWidth;
    final centerX = box.center.dx / frameWidth;
    final centerY = box.center.dy / frameHeight;

    if (widthRatio < 0.30) return FaceGuidance.tooFar;
    if (widthRatio > 0.70) return FaceGuidance.tooClose;
    if ((centerX - 0.5).abs() > 0.15 || (centerY - 0.45).abs() > 0.18) return FaceGuidance.offCenter;
    if ((face.headEulerAngleY ?? 0).abs() > 18) return FaceGuidance.lookStraight;
    return FaceGuidance.good;
  }

  void dispose() {
    _closed = true;
    _detector.close();
    guidance.dispose();
  }
}
