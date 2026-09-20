import 'package:flutter/material.dart';

/// Heading that introduces a group of rows on a screen ("Recent activity",
/// "Attendance history"). Shared so the staff and admin sections read alike.
class SectionTitle extends StatelessWidget {
  const SectionTitle(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 12),
      child: Text(text, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
    );
  }
}
