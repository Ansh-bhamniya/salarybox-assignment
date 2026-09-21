import 'dart:ui';
import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';

/// Wraps a live camera frame for ML Kit, or null if the frame is in a format it
/// can't read straight from the stream (single-plane NV21 on Android, BGRA on
/// iOS). Shared by everything that analyses the preview stream.
InputImage? inputImageFromCameraImage(CameraImage image, int sensorOrientation) {
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

/// The frame's size as ML Kit reports face boxes in it: upright.
///
/// Android hands over the raw sensor buffer, which is sideways for a portrait
/// phone (sensor orientation 90/270), so its width and height swap. iOS delivers
/// the stream already upright whatever the sensor orientation says; swapping
/// there put every face at the wrong place (measured on an iPhone: a centred
/// face read as x 0.28, y 0.9).
Size uprightFrameSize(CameraImage image, int sensorOrientation) => uprightSizeOf(
  width: image.width,
  height: image.height,
  sensorOrientation: sensorOrientation,
  streamIsUpright: defaultTargetPlatform == TargetPlatform.iOS,
);

/// [uprightFrameSize] without the camera types, so it can be tested.
Size uprightSizeOf({
  required int width,
  required int height,
  required int sensorOrientation,
  required bool streamIsUpright,
}) {
  final sideways = !streamIsUpright && (sensorOrientation == 90 || sensorOrientation == 270);
  return Size((sideways ? height : width).toDouble(), (sideways ? width : height).toDouble());
}
