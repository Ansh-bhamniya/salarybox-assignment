import 'dart:ui';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/services/camera_input_image.dart';

void main() {
  group('uprightSizeOf (where ML Kit reports face boxes)', () {
    test('Android: the sensor buffer is sideways, so width and height swap', () {
      final size = uprightSizeOf(width: 1280, height: 720, sensorOrientation: 270, streamIsUpright: false);
      expect(size, const Size(720, 1280));
    });

    test('Android with an upright sensor orientation keeps the buffer as it is', () {
      final size = uprightSizeOf(width: 720, height: 1280, sensorOrientation: 0, streamIsUpright: false);
      expect(size, const Size(720, 1280));
    });

    test('iOS: the stream is already upright, so nothing swaps even though the sensor says 270', () {
      final size = uprightSizeOf(width: 720, height: 1280, sensorOrientation: 270, streamIsUpright: true);
      expect(size, const Size(720, 1280));
    });
  });
}
