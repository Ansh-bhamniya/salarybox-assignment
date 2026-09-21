import 'dart:math';
import 'package:flutter/material.dart';

/// The line under the face oval that shows how far to turn. It starts at the
/// middle (looking straight) and a bar grows from there toward the side the head
/// is turned to, with a dot at its end. The green zone is where this photo should
/// be taken from.
///
/// Positive degrees are toward the person's own left, and that is drawn to the
/// left, because the preview is a mirror: turn your head toward the left and the
/// bar grows left with you.
class TurnMeter extends StatelessWidget {
  const TurnMeter({
    super.key,
    required this.turnDegrees,
    required this.targetMin,
    required this.targetMax,
    required this.inPosition,
    this.range = 40,
  });

  /// Where the head is now, or null if no face is seen.
  final double? turnDegrees;

  /// The zone that is right for this photo.
  final double targetMin;
  final double targetMax;

  /// The head is in the zone and being held.
  final bool inPosition;

  /// Degrees from the middle to either end of the line.
  final double range;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final labelStyle = Theme.of(
      context,
    ).textTheme.labelSmall?.copyWith(color: Colors.white70, fontWeight: FontWeight.w700);

    return Semantics(
      label: inPosition ? 'Head in the right position, hold still' : 'Turn guide',
      child: ExcludeSemantics(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              height: 28,
              width: double.infinity,
              // Glide between readings instead of jumping.
              child: TweenAnimationBuilder<double>(
                tween: Tween<double>(end: turnDegrees ?? 0),
                duration: const Duration(milliseconds: 90),
                builder: (context, animated, _) => CustomPaint(
                  painter: _TurnMeterPainter(
                    turnDegrees: turnDegrees == null ? null : animated,
                    targetMin: targetMin,
                    targetMax: targetMax,
                    inPosition: inPosition,
                    range: range,
                    accent: scheme.primaryFixedDim,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 2),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('← LEFT', style: labelStyle),
                Text('RIGHT →', style: labelStyle),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _TurnMeterPainter extends CustomPainter {
  const _TurnMeterPainter({
    required this.turnDegrees,
    required this.targetMin,
    required this.targetMax,
    required this.inPosition,
    required this.range,
    required this.accent,
  });

  final double? turnDegrees;
  final double targetMin;
  final double targetMax;
  final bool inPosition;
  final double range;
  final Color accent;

  @override
  void paint(Canvas canvas, Size size) {
    final mid = size.width / 2;
    const centerY = 12.0;

    // Positive degrees (the person's left) go to the left of the line.
    double xOf(double degrees) => mid - (degrees.clamp(-range, range) / range) * mid;

    // The track.
    canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromLTWH(0, centerY - 3, size.width, 6), const Radius.circular(3)),
      Paint()..color = Colors.white24,
    );

    // The zone this photo is taken from.
    final zone = RRect.fromRectAndRadius(
      Rect.fromLTRB(xOf(targetMax), centerY - 9, xOf(targetMin), centerY + 9),
      const Radius.circular(9),
    );
    canvas.drawRRect(zone, Paint()..color = accent.withValues(alpha: inPosition ? 0.8 : 0.4));
    canvas.drawRRect(
      zone,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..color = accent,
    );

    final degrees = turnDegrees;
    if (degrees != null) {
      // The bar grows out of the middle toward the head.
      final x = xOf(degrees);
      if ((x - mid).abs() > 0.5) {
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTRB(min(mid, x), centerY - 4, max(mid, x), centerY + 4),
            const Radius.circular(4),
          ),
          Paint()..color = (inPosition ? accent : Colors.white).withValues(alpha: 0.85),
        );
      }
    }

    // Straight ahead.
    canvas.drawLine(
      Offset(mid, centerY - 8),
      Offset(mid, centerY + 8),
      Paint()
        ..color = Colors.white70
        ..strokeWidth = 2,
    );

    // The head.
    if (degrees != null) {
      final x = xOf(degrees);
      canvas.drawCircle(Offset(x, centerY), 10, Paint()..color = Colors.black45);
      canvas.drawCircle(Offset(x, centerY), 8, Paint()..color = inPosition ? accent : Colors.white);
    }
  }

  @override
  bool shouldRepaint(_TurnMeterPainter old) =>
      old.turnDegrees != turnDegrees ||
      old.targetMin != targetMin ||
      old.targetMax != targetMax ||
      old.inPosition != inPosition ||
      old.range != range;
}
