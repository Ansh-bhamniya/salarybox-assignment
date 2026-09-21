import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/services/liveness/turn_reading.dart';

void main() {
  // The iPhone convention: turning to your left makes the angle negative while
  // the person-space nose offset goes positive.
  group('the sign', () {
    test('uses the measured default before anything is learned: a negative angle is the left', () {
      final reading = TurnReading(smoothing: 1);
      expect(reading.read(-6, 0.05), closeTo(6, 1e-9));
      expect(reading.read(6, -0.05), closeTo(-6, 1e-9));
    });

    test('learns which way the angle runs from the first clear turn', () {
      // A device where the angle and the nose offset go the same way.
      final reading = TurnReading(smoothing: 1);
      reading.read(20, 0.25);

      expect(reading.read(8, 0.02), closeTo(8, 1e-9), reason: 'small readings now follow the learned sign');
      expect(reading.read(-8, -0.02), closeTo(-8, 1e-9));
    });

    test('a small or unconvincing turn teaches nothing', () {
      final reading = TurnReading(smoothing: 1);
      reading.read(6, 0.3); // angle too small to learn from
      reading.read(20, 0.05); // nose barely moved

      expect(reading.read(-5, 0), closeTo(5, 1e-9), reason: 'still the default');
    });

    test('is not thrown by the nose offset flickering around zero', () {
      final reading = TurnReading(smoothing: 1);
      for (var i = 0; i < 10; i++) {
        expect(reading.read(-2, i.isEven ? 0.03 : -0.03), closeTo(2, 1e-9));
      }
    });
  });

  group('smoothing', () {
    test('the first reading is taken as it is', () {
      expect(TurnReading().read(-10, 0.2), closeTo(10, 1e-9));
    });

    test('later readings move only part of the way, so the line does not jump', () {
      final reading = TurnReading(smoothing: 0.5);
      reading.read(0, 0);

      expect(reading.read(-20, 0.3), closeTo(10, 1e-9));
      expect(reading.read(-20, 0.3), closeTo(15, 1e-9));
    });

    test('settles on a steady reading', () {
      final reading = TurnReading();
      var v = 0.0;
      for (var i = 0; i < 20; i++) {
        v = reading.read(-20, 0.3);
      }
      expect(v, closeTo(20, 0.01));
    });

    test('clearing the smoothing starts the next reading fresh but keeps what was learned', () {
      final reading = TurnReading();
      reading.read(20, 0.25); // learns: same direction
      reading.clearSmoothing();

      expect(reading.current, isNull);
      expect(reading.read(10, 0.1), closeTo(10, 1e-9));
    });

    test('reset forgets what was learned as well', () {
      final reading = TurnReading(smoothing: 1);
      reading.read(20, 0.25);
      reading.reset();

      expect(reading.read(10, 0.1), closeTo(-10, 1e-9), reason: 'back to the default');
    });
  });
}
