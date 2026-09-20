import 'package:flutter/material.dart';
import '../config/theme/app_radius.dart';

/// "Step 1 of 2" header with one rounded segment per step; finished and
/// current steps are filled, the rest stay muted. Segments animate as the
/// step changes.
class StepProgress extends StatelessWidget {
  const StepProgress({super.key, required this.step, required this.total, required this.title})
    : assert(step >= 1 && step <= total);

  final int step;
  final int total;

  /// What this step is about, shown at the right ("Staff details").
  final String title;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Semantics(
      label: 'Step $step of $total, $title',
      child: ExcludeSemantics(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text('Step $step of $total', style: theme.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w800)),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    title,
                    textAlign: TextAlign.end,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelLarge?.copyWith(color: scheme.onSurfaceVariant),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                for (var i = 0; i < total; i++) ...[
                  if (i > 0) const SizedBox(width: 8),
                  Expanded(
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 300),
                      curve: Curves.easeOut,
                      height: 4,
                      decoration: BoxDecoration(
                        color: i < step ? scheme.primary : scheme.outlineVariant,
                        borderRadius: AppRadius.pillBorder,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}
