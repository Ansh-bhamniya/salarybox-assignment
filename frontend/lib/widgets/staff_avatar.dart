import 'package:flutter/material.dart';

/// Enrolment photo when there is one, otherwise the person's initial — a
/// name on a tinted circle is far easier to scan in a list than a generic
/// silhouette icon.
class StaffAvatar extends StatelessWidget {
  const StaffAvatar({super.key, required this.name, this.photoUrl, this.radius = 24});

  final String name;
  final String? photoUrl;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final trimmed = name.trim();
    final initial = trimmed.isEmpty ? '?' : trimmed[0].toUpperCase();

    return CircleAvatar(
      radius: radius,
      backgroundColor: scheme.primaryContainer,
      foregroundColor: scheme.onPrimaryContainer,
      backgroundImage: photoUrl != null ? NetworkImage(photoUrl!) : null,
      child: photoUrl == null
          ? Text(initial, style: TextStyle(fontSize: radius * 0.8, fontWeight: FontWeight.w600))
          : null,
    );
  }
}
