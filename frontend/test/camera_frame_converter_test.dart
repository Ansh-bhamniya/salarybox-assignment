import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' show Rect;
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/services/camera_frame_converter.dart';
import 'package:frontend/services/liveness/camera_frame.dart';
import 'package:image/image.dart' as img;

/// A BGRA frame whose pixel (x, y) has a colour that says where it is.
CameraFrame _bgra({int width = 3, int height = 2, int padding = 4, int rotation = 0}) {
  final stride = width * 4 + padding;
  final bytes = Uint8List(stride * height);
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      final o = y * stride + x * 4;
      bytes[o] = 50; // blue
      bytes[o + 1] = 20 + y * 100; // green
      bytes[o + 2] = 10 + x * 80; // red
      bytes[o + 3] = 255;
    }
  }
  return CameraFrame(
    bytes: bytes,
    width: width,
    height: height,
    bytesPerRow: stride,
    format: FrameFormat.bgra8888,
    rotationDegrees: rotation,
  );
}

/// The colour [_bgra] gives pixel (x, y).
List<int> _expected(int x, int y) => [10 + x * 80, 20 + y * 100, 50];
List<int> _rgb(img.Image image, int x, int y) {
  final p = image.getPixel(x, y);
  return [p.r.toInt(), p.g.toInt(), p.b.toInt()];
}

/// An NV21 frame made of uniform 2×2 blocks of colour, with padded rows.
CameraFrame _nv21(List<List<int>> blocks, {int width = 4, int height = 2, int padding = 2, int rotation = 0}) {
  final stride = width + padding;
  final bytes = Uint8List(stride * height + stride * (height ~/ 2));
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      final c = blocks[x ~/ 2];
      bytes[y * stride + x] = (0.299 * c[0] + 0.587 * c[1] + 0.114 * c[2]).round();
    }
  }
  final chroma = stride * height;
  for (var b = 0; b < width ~/ 2; b++) {
    final c = blocks[b];
    final u = 128 + (-0.168736 * c[0] - 0.331264 * c[1] + 0.5 * c[2]);
    final v = 128 + (0.5 * c[0] - 0.418688 * c[1] - 0.081312 * c[2]);
    bytes[chroma + b * 2] = v.round(); // NV21 is V then U
    bytes[chroma + b * 2 + 1] = u.round();
  }
  return CameraFrame(
    bytes: bytes,
    width: width,
    height: height,
    bytesPerRow: stride,
    format: FrameFormat.nv21,
    rotationDegrees: rotation,
  );
}

void main() {
  group('BGRA frames (iPhone)', () {
    test('become an upright picture with the right colours, ignoring row padding', () {
      final image = frameToUprightImage(_bgra(), mirrored: false);

      expect(image.width, 3);
      expect(image.height, 2);
      for (var y = 0; y < 2; y++) {
        for (var x = 0; x < 3; x++) {
          expect(_rgb(image, x, y), _expected(x, y), reason: 'pixel ($x,$y)');
        }
      }
    });

    test('a mirrored stream is flipped back, so it faces the way the enrolment photos do', () {
      final image = frameToUprightImage(_bgra(), mirrored: true);

      for (var y = 0; y < 2; y++) {
        for (var x = 0; x < 3; x++) {
          expect(_rgb(image, x, y), _expected(2 - x, y), reason: 'pixel ($x,$y)');
        }
      }
    });
  });

  group('rotating a sideways sensor buffer (Android)', () {
    test('90 degrees clockwise', () {
      final image = frameToUprightImage(_bgra(rotation: 90), mirrored: false);

      expect(image.width, 2);
      expect(image.height, 3);
      for (var y = 0; y < 3; y++) {
        for (var x = 0; x < 2; x++) {
          // Clockwise: the new (x, y) came from old (y, oldHeight - 1 - x).
          expect(_rgb(image, x, y), _expected(y, 1 - x), reason: 'pixel ($x,$y)');
        }
      }
    });

    test('270 degrees clockwise', () {
      final image = frameToUprightImage(_bgra(rotation: 270), mirrored: false);

      expect(image.width, 2);
      expect(image.height, 3);
      for (var y = 0; y < 3; y++) {
        for (var x = 0; x < 2; x++) {
          expect(_rgb(image, x, y), _expected(2 - y, x), reason: 'pixel ($x,$y)');
        }
      }
    });

    test('rotating and flipping both happen, rotation first', () {
      final image = frameToUprightImage(_bgra(rotation: 90), mirrored: true);
      // After the 90° turn the picture is 2 wide, then it is flipped left to right.
      for (var y = 0; y < 3; y++) {
        for (var x = 0; x < 2; x++) {
          expect(_rgb(image, x, y), _expected(y, 1 - (1 - x)), reason: 'pixel ($x,$y)');
        }
      }
    });
  });

  group('NV21 frames (Android)', () {
    void expectClose(List<int> actual, List<int> want, {int by = 4}) {
      for (var i = 0; i < 3; i++) {
        expect((actual[i] - want[i]).abs(), lessThanOrEqualTo(by), reason: 'channel $i: $actual vs $want');
      }
    }

    test('are turned back into the colours they were made from', () {
      final red = [200, 50, 50], blue = [50, 50, 200];
      final image = frameToUprightImage(_nv21([red, blue]), mirrored: false);

      for (var y = 0; y < 2; y++) {
        expectClose(_rgb(image, 0, y), red);
        expectClose(_rgb(image, 1, y), red);
        expectClose(_rgb(image, 2, y), blue);
        expectClose(_rgb(image, 3, y), blue);
      }
    });

    test('grey stays grey and black and white keep their ends', () {
      final image = frameToUprightImage(
        _nv21([
          [128, 128, 128],
          [255, 255, 255],
        ]),
        mirrored: false,
      );
      expectClose(_rgb(image, 0, 0), [128, 128, 128]);
      expectClose(_rgb(image, 3, 1), [255, 255, 255], by: 3);
    });

    test('rotate like any other frame', () {
      final red = [200, 50, 50], blue = [50, 50, 200];
      final image = frameToUprightImage(_nv21([red, blue], rotation: 90), mirrored: false);

      expect(image.width, 2);
      expect(image.height, 4);
      // Turned clockwise, the red left half is now the top half.
      expectClose(_rgb(image, 0, 0), red);
      expectClose(_rgb(image, 1, 1), red);
      expectClose(_rgb(image, 0, 3), blue);
    });
  });

  group('face boxes', () {
    test('are unchanged for a stream that is not mirrored', () {
      const box = Rect.fromLTWH(100, 200, 300, 400);
      expect(boxAfterFlip(box, 720, mirrored: false), box);
    });

    test('move to the other side when the picture is flipped, keeping their size', () {
      const box = Rect.fromLTWH(100, 200, 300, 400); // 100..400 of 720
      final flipped = boxAfterFlip(box, 720, mirrored: true);

      expect(flipped, const Rect.fromLTWH(320, 200, 300, 400)); // 320..620
      expect(flipped.center.dx, 720 - box.center.dx);
    });
  });

  group('the model input', () {
    test('is 112 x 112 x 3, scaled to about -1..1', () {
      final image = img.Image(width: 300, height: 300);
      img.fill(image, color: img.ColorRgb8(200, 100, 50));

      final tensor = faceTensorFromImage(image, 100, 100, 100, 100);

      expect(tensor.length, 112 * 112 * 3);
      expect(tensor[0], closeTo((200 - 128) / 128, 1e-6));
      expect(tensor[1], closeTo((100 - 128) / 128, 1e-6));
      expect(tensor[2], closeTo((50 - 128) / 128, 1e-6));
      expect(tensor.every((v) => v >= -1 && v <= 1), isTrue);
    });

    test('is cut from around the face box: a face in the blue half sees only blue', () {
      final image = img.Image(width: 400, height: 400);
      img.fill(image, color: img.ColorRgb8(255, 0, 0));
      img.fillRect(image, x1: 200, y1: 0, x2: 399, y2: 399, color: img.ColorRgb8(0, 0, 255));

      // A 60 px face centred at x=300: the 72 px crop (1.2x) stays inside the blue half.
      final tensor = faceTensorFromImage(image, 270, 170, 60, 60);

      for (final at in [0, 112 * 56 * 3, 112 * 112 * 3 - 3]) {
        expect(tensor[at], closeTo(-1, 1e-6), reason: 'red at $at');
        expect(tensor[at + 2], closeTo((255 - 128) / 128, 1e-6), reason: 'blue at $at');
      }
    });

    test('a face box at the edge of the picture is pulled inside it instead of failing', () {
      final image = img.Image(width: 200, height: 200);
      final tensor = faceTensorFromImage(image, 0, 0, 80, 80);
      expect(tensor.length, 112 * 112 * 3);

      final huge = faceTensorFromImage(image, -50, -50, 500, 500);
      expect(huge.length, 112 * 112 * 3);
    });
  });

  group('cutting a face out of a frame', () {
    /// Left half red, right half blue, as a BGRA frame.
    CameraFrame halves({int rotation = 0}) {
      const width = 40, height = 40;
      final bytes = Uint8List(width * height * 4);
      for (var y = 0; y < height; y++) {
        for (var x = 0; x < width; x++) {
          final o = (y * width + x) * 4;
          final blue = x >= width ~/ 2;
          bytes[o] = blue ? 255 : 0;
          bytes[o + 2] = blue ? 0 : 255;
          bytes[o + 3] = 255;
        }
      }
      return CameraFrame(
        bytes: bytes,
        width: width,
        height: height,
        bytesPerRow: width * 4,
        format: FrameFormat.bgra8888,
        rotationDegrees: rotation,
      );
    }

    test('finds the face where ML Kit said it was, for a stream that is not mirrored', () async {
      // The face box sits in the blue (right) half of the stream.
      final crop = await cropFrameForEmbedding(halves(), const Rect.fromLTWH(24, 12, 10, 10), mirrored: false);

      expect(crop.tensor[0], closeTo(-1, 1e-6), reason: 'no red');
      expect(crop.tensor[2], closeTo((255 - 128) / 128, 1e-6), reason: 'blue');
    });

    test('follows the face through the flip of a mirrored stream', () async {
      // Same box on the stream; the picture is then flipped, but the box moves with it.
      final crop = await cropFrameForEmbedding(halves(), const Rect.fromLTWH(24, 12, 10, 10), mirrored: true);

      expect(crop.tensor[0], closeTo(-1, 1e-6));
      expect(crop.tensor[2], closeTo((255 - 128) / 128, 1e-6));
    });

    test('a box that was not moved with the flip would have landed on the wrong colour', () {
      // The reason boxAfterFlip exists: the same pixels, flipped, put red where the box is.
      final image = frameToUprightImage(halves(), mirrored: true);
      final wrong = faceTensorFromImage(image, 24, 12, 10, 10);
      final right = faceTensorFromImage(
        image,
        boxAfterFlip(const Rect.fromLTWH(24, 12, 10, 10), 40, mirrored: true).left,
        12,
        10,
        10,
      );

      expect(wrong[0], closeTo((255 - 128) / 128, 1e-6), reason: 'red: wrong side');
      expect(right[2], closeTo((255 - 128) / 128, 1e-6), reason: 'blue: right side');
    });

    test('saves the whole upright picture as a JPEG when asked', () async {
      final dir = Directory.systemTemp.createTempSync('frame_test');
      addTearDown(() => dir.deleteSync(recursive: true));
      final path = '${dir.path}/final.jpg';

      final crop = await cropFrameForEmbedding(
        halves(rotation: 90),
        const Rect.fromLTWH(10, 10, 10, 10),
        mirrored: true,
        saveJpegTo: path,
      );

      expect(crop.jpegPath, path);
      final decoded = img.decodeJpg(File(path).readAsBytesSync())!;
      expect(decoded.width, 40);
      expect(decoded.height, 40);
    });

    test('writes nothing unless asked', () async {
      final crop = await cropFrameForEmbedding(halves(), const Rect.fromLTWH(10, 10, 10, 10), mirrored: false);
      expect(crop.jpegPath, isNull);
    });
  });

  test('a real-sized iPhone frame is converted quickly enough to do for a handful of frames', () {
    // 720x1280 BGRA. Well inside a fraction of a second on a laptop; the phone is slower but only does 4.
    final frame = CameraFrame(
      bytes: Uint8List(720 * 1280 * 4),
      width: 720,
      height: 1280,
      bytesPerRow: 720 * 4,
      format: FrameFormat.bgra8888,
      rotationDegrees: 0,
    );
    final watch = Stopwatch()..start();
    final image = frameToUprightImage(frame, mirrored: true);
    faceTensorFromImage(image, 200, 400, 300, 380);
    watch.stop();

    expect(image.width, 720);
    expect(watch.elapsedMilliseconds, lessThan(2000), reason: 'took ${watch.elapsedMilliseconds} ms');
  });
}
