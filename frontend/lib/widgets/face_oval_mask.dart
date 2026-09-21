import 'dart:math';
import 'package:flutter/material.dart';

/// The oval the face is framed in, as a rect within a screen of [size].
Rect faceOvalRect(Size size) {
  final width = size.width * 0.72;
  final height = width * 1.3;
  return Rect.fromCenter(center: Offset(size.width / 2, size.height * 0.44), width: width, height: height);
}

/// Darkens everything outside the framing oval and outlines it in [ringColor].
/// Shared by every screen that asks for a face in the oval. With a [progress]
/// above zero an arc in [progressColor] fills the ring clockwise from the top
/// (used to show how much of a hold is done).
class FaceOvalMaskPainter extends CustomPainter {
  const FaceOvalMaskPainter({required this.ringColor, this.progress = 0, this.progressColor = Colors.white});

  final Color ringColor;
  final double progress;
  final Color progressColor;

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

    if (progress > 0) {
      final arc = Path()..arcTo(oval, -pi / 2, 2 * pi * progress.clamp(0.0, 1.0), true);
      canvas.drawPath(
        arc,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 7
          ..strokeCap = StrokeCap.round
          ..color = progressColor,
      );
    }
  }

  @override
  bool shouldRepaint(FaceOvalMaskPainter oldDelegate) =>
      oldDelegate.ringColor != ringColor ||
      oldDelegate.progress != progress ||
      oldDelegate.progressColor != progressColor;
}
