import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/widgets/face_oval_mask.dart';

void main() {
  group('FaceOvalMaskPainter', () {
    test('repaints when the split or what is done changes', () {
      const base = FaceOvalMaskPainter(ringColor: Colors.white, segments: 3, segmentsDone: 1, progress: 0.5);

      expect(base.shouldRepaint(base), isFalse);
      expect(
        base.shouldRepaint(
          const FaceOvalMaskPainter(ringColor: Colors.white, segments: 3, segmentsDone: 2, progress: 0.5),
        ),
        isTrue,
      );
      expect(
        base.shouldRepaint(
          const FaceOvalMaskPainter(ringColor: Colors.white, segments: 4, segmentsDone: 1, progress: 0.5),
        ),
        isTrue,
      );
    });

    testWidgets('draws a split ring, a whole ring and an unfinished one without trouble', (tester) async {
      for (final painter in const [
        FaceOvalMaskPainter(ringColor: Colors.white),
        FaceOvalMaskPainter(ringColor: Colors.white, progress: 0.4),
        FaceOvalMaskPainter(ringColor: Colors.white, segments: 3),
        FaceOvalMaskPainter(ringColor: Colors.white, segments: 3, segmentsDone: 1, progress: 0.5),
        FaceOvalMaskPainter(ringColor: Colors.white, segments: 3, segmentsDone: 3),
        FaceOvalMaskPainter(ringColor: Colors.white, segments: 4, segmentsDone: 9, progress: 2),
      ]) {
        await tester.pumpWidget(
          Directionality(
            textDirection: TextDirection.ltr,
            child: CustomPaint(painter: painter),
          ),
        );
        expect(tester.takeException(), isNull);
      }
    });
  });
}
