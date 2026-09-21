import 'dart:io';
import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' show Rect;
import 'package:image/image.dart' as img;
import './liveness/camera_frame.dart';

/// The model's input side, and how much wider than the detected face box the
/// square crop is (a little forehead and chin, like the model's training crops).
const faceInputSize = 112;
const faceCropMargin = 1.2;

/// Turns a raw camera frame into an upright picture the way a person would see
/// it, the same way round as the enrolment photos: rotated upright and, if the
/// device's stream is mirrored (as an iPhone's front camera is), flipped back.
img.Image frameToUprightImage(CameraFrame frame, {required bool mirrored}) {
  var image = switch (frame.format) {
    FrameFormat.bgra8888 => _fromBgra(frame),
    FrameFormat.nv21 => _fromNv21(frame),
  };
  if (frame.rotationDegrees != 0) image = img.copyRotate(image, angle: frame.rotationDegrees);
  if (mirrored) image = img.flipHorizontal(image);
  return image;
}

/// Where a face box that ML Kit reported on the stream's own (upright) picture
/// sits once that picture has been flipped back.
Rect boxAfterFlip(Rect box, double uprightWidth, {required bool mirrored}) =>
    mirrored ? Rect.fromLTWH(uprightWidth - box.right, box.top, box.width, box.height) : box;

/// The model's input for the face in [image]: a square around [box], resized to
/// 112×112, RGB scaled to roughly -1..1 (`(p - 128) / 128`), the way the model
/// was trained. Static and free of plugins so it can run in a background isolate.
Float32List faceTensorFromImage(img.Image image, double left, double top, double width, double height) {
  final side = min((max(width, height) * faceCropMargin).floor(), min(image.width, image.height));
  final centerX = left + width / 2;
  final centerY = top + height / 2;
  final x = (centerX - side / 2).round().clamp(0, image.width - side);
  final y = (centerY - side / 2).round().clamp(0, image.height - side);

  final crop = img.copyCrop(image, x: x, y: y, width: side, height: side);
  final resized = img.copyResize(
    crop,
    width: faceInputSize,
    height: faceInputSize,
    interpolation: img.Interpolation.linear,
  );

  final tensor = Float32List(faceInputSize * faceInputSize * 3);
  var i = 0;
  for (final pixel in resized) {
    tensor[i++] = (pixel.r - 128) / 128;
    tensor[i++] = (pixel.g - 128) / 128;
    tensor[i++] = (pixel.b - 128) / 128;
  }
  return tensor;
}

/// What cutting a face out of a frame produces.
class FrameCrop {
  const FrameCrop({required this.tensor, this.jpegPath});

  final Float32List tensor;

  /// The whole upright picture as a JPEG, if one was asked for.
  final String? jpegPath;
}

/// Cuts the face at [faceBox] (as ML Kit reported it on the stream) out of
/// [frame], off the UI isolate. If [saveJpegTo] is given the whole upright
/// picture is also written there, for use as the attendance photo.
Future<FrameCrop> cropFrameForEmbedding(CameraFrame frame, Rect faceBox, {required bool mirrored, String? saveJpegTo}) {
  final left = faceBox.left, top = faceBox.top, width = faceBox.width, height = faceBox.height;
  return Isolate.run(() {
    final image = frameToUprightImage(frame, mirrored: mirrored);
    final box = boxAfterFlip(Rect.fromLTWH(left, top, width, height), image.width.toDouble(), mirrored: mirrored);
    final tensor = faceTensorFromImage(image, box.left, box.top, box.width, box.height);

    if (saveJpegTo != null) File(saveJpegTo).writeAsBytesSync(img.encodeJpg(image, quality: 90));
    return FrameCrop(tensor: tensor, jpegPath: saveJpegTo);
  });
}

// ---- pixel formats ----------------------------------------------------------

img.Image _fromBgra(CameraFrame f) => img.Image.fromBytes(
  width: f.width,
  height: f.height,
  bytes: f.bytes.buffer,
  bytesOffset: f.bytes.offsetInBytes,
  rowStride: f.bytesPerRow,
  numChannels: 4,
  order: img.ChannelOrder.bgra,
);

/// NV21: a full-size luma (Y) plane, then interleaved V,U samples for each 2×2
/// block of pixels.
img.Image _fromNv21(CameraFrame f) {
  final image = img.Image(width: f.width, height: f.height);
  final bytes = f.bytes;
  final stride = f.bytesPerRow;
  final chromaStart = f.height * stride;

  int clamp(double v) => v < 0 ? 0 : (v > 255 ? 255 : v.round());

  for (var y = 0; y < f.height; y++) {
    final chromaRow = chromaStart + (y >> 1) * stride;
    for (var x = 0; x < f.width; x++) {
      final luma = bytes[y * stride + x];
      final chroma = chromaRow + (x & ~1);
      final v = bytes[chroma] - 128;
      final u = bytes[chroma + 1] - 128;
      image.setPixelRgb(
        x,
        y,
        clamp(luma + 1.402 * v),
        clamp(luma - 0.344136 * u - 0.714136 * v),
        clamp(luma + 1.772 * u),
      );
    }
  }
  return image;
}
