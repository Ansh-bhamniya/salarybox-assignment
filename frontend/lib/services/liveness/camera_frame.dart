import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';

enum FrameFormat { bgra8888, nv21 }

/// A private copy of one live camera frame, kept so a face can be cut out of it
/// later. The camera reuses its buffers, so anything that outlives the frame
/// callback must copy — that is what this is.
class CameraFrame {
  const CameraFrame({
    required this.bytes,
    required this.width,
    required this.height,
    required this.bytesPerRow,
    required this.format,
    required this.rotationDegrees,
  });

  final Uint8List bytes;
  final int width;
  final int height;

  /// Bytes from the start of one pixel row to the next (rows can be padded).
  final int bytesPerRow;

  final FrameFormat format;

  /// How many degrees clockwise the buffer must be turned to stand upright:
  /// nothing on iOS (the stream arrives upright), the sensor's orientation on
  /// Android (the buffer is the raw, sideways sensor image).
  final int rotationDegrees;

  /// Copies [image] (single-plane BGRA on iOS, NV21 on Android), or null for a
  /// format this can't read.
  static CameraFrame? fromCameraImage(CameraImage image, int sensorOrientation) {
    if (image.planes.length != 1) return null;

    final FrameFormat format;
    switch (image.format.group) {
      case ImageFormatGroup.bgra8888:
        format = FrameFormat.bgra8888;
      case ImageFormatGroup.nv21:
        format = FrameFormat.nv21;
      default:
        return null;
    }

    final plane = image.planes.first;
    return CameraFrame(
      bytes: Uint8List.fromList(plane.bytes),
      width: image.width,
      height: image.height,
      bytesPerRow: plane.bytesPerRow,
      format: format,
      rotationDegrees: defaultTargetPlatform == TargetPlatform.iOS ? 0 : sensorOrientation,
    );
  }
}
