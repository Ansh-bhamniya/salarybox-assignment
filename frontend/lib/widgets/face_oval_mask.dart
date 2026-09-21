import 'dart:math';
import 'package:flutter/material.dart';

/// The oval the face is framed in, as a rect within a screen of [size].
Rect faceOvalRect(Size size) {
  final width = size.width * 0.72;
  final height = width * 1.3;
  return Rect.fromCenter(center: Offset(size.width / 2, size.height * 0.44), width: width, height: height);
}

/// Darkens everything outside the framing oval and outlines it in [ringColor].
/// Shared by every screen that asks for a face in the oval.
///
/// The ring can show progress: it is split into [segments] equal pieces (one per
/// step, with small gaps), the first [segmentsDone] are filled in [progressColor],
/// and [progress] (0..1) fills the next piece clockwise from where it starts.
/// The first piece starts at the top. With one segment the whole ring is one piece.
class FaceOvalMaskPainter extends CustomPainter {
  const FaceOvalMaskPainter({
    required this.ringColor,
    this.progress = 0,
    this.progressColor = Colors.white,
    this.segments = 1,
    this.segmentsDone = 0,
  }) : assert(segments >= 1);

  final Color ringColor;
  final double progress;
  final Color progressColor;
  final int segments;
  final int segmentsDone;

  /// The empty space left between two pieces of a split ring, in radians.
  static const gap = 0.16;

  @override
  void paint(Canvas canvas, Size size) {
    final oval = faceOvalRect(size);

    final scrim = Path()
      ..fillType = PathFillType.evenOdd
      ..addRect(Offset.zero & size)
      ..addOval(oval);
    canvas.drawPath(scrim, Paint()..color = Colors.black.withValues(alpha: 0.55));

    canvas.drawOval(
      oval,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..color = ringColor,
    );

    final fill = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 7
      ..strokeCap = StrokeCap.round
      ..color = progressColor;

    if (segments == 1) {
      final amount = segmentsDone >= 1 ? 1.0 : progress.clamp(0.0, 1.0);
      if (amount > 0) canvas.drawPath(Path()..arcTo(oval, -pi / 2, 2 * pi * amount, true), fill);
      return;
    }

    // Split ring: an empty track for every piece, then what is done on top of it.
    final track = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 7
      ..strokeCap = StrokeCap.round
      ..color = Colors.white.withValues(alpha: 0.3);
    final piece = 2 * pi / segments;
    for (var i = 0; i < segments; i++) {
      final start = -pi / 2 + i * piece + gap / 2;
      final length = piece - gap;
      canvas.drawPath(Path()..arcTo(oval, start, length, true), track);

      final amount = i < segmentsDone ? 1.0 : (i == segmentsDone ? progress.clamp(0.0, 1.0) : 0.0);
      if (amount > 0) canvas.drawPath(Path()..arcTo(oval, start, length * amount, true), fill);
    }
  }

  @override
  bool shouldRepaint(FaceOvalMaskPainter oldDelegate) =>
      oldDelegate.ringColor != ringColor ||
      oldDelegate.progress != progress ||
      oldDelegate.progressColor != progressColor ||
      oldDelegate.segments != segments ||
      oldDelegate.segmentsDone != segmentsDone;
}
