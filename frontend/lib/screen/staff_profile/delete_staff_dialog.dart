import 'package:flutter/material.dart';

/// Asks the admin to confirm deleting a staff member, saying what goes with them.
/// True only if they chose to delete.
Future<bool> confirmDeleteStaff(BuildContext context, {required String name, required int attendanceRecords}) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) {
      final scheme = Theme.of(context).colorScheme;
      final records = attendanceRecords == 1 ? '1 attendance record' : '$attendanceRecords attendance records';

      return AlertDialog(
        title: Text('Delete $name?'),
        content: Text(
          'This permanently removes $name, their enrolled face and $records, with the selfies. It cannot be undone.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: scheme.error),
            child: const Text('Delete'),
          ),
        ],
      );
    },
  );
  return confirmed ?? false;
}
