import 'package:flutter/material.dart';
import '../../models/duplicate_match.dart';

/// Reasons an admin can give for replacing someone's enrolled face. Kept in
/// the audit log next to the old face, which is revoked but never deleted.
const reEnrolReasons = [
  'Appearance changed (glasses, beard, hairstyle…)',
  'Recognition keeps failing',
  'The original photos were poor',
  'Other',
];

/// Asks why a person is being re-enrolled. Null if the admin backed out.
Future<String?> askReEnrolReason(BuildContext context) {
  return showDialog<String>(
    context: context,
    builder: (context) => SimpleDialog(
      title: const Text('Why re-enrol this face?'),
      children: [
        for (final reason in reEnrolReasons)
          SimpleDialogOption(onPressed: () => Navigator.pop(context, reason), child: Text(reason)),
      ],
    ),
  );
}

/// Warns that the face being enrolled looks like someone already enrolled, and
/// asks for a reason if the admin wants to go ahead anyway. Returns that reason,
/// or null if they cancelled.
Future<String?> confirmDuplicate(BuildContext context, List<DuplicateMatch> matches) {
  return showDialog<String>(
    context: context,
    builder: (context) => _DuplicateDialog(matches: matches),
  );
}

class _DuplicateDialog extends StatefulWidget {
  const _DuplicateDialog({required this.matches});

  final List<DuplicateMatch> matches;

  @override
  State<_DuplicateDialog> createState() => _DuplicateDialogState();
}

class _DuplicateDialogState extends State<_DuplicateDialog> {
  final _reason = TextEditingController();

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AlertDialog(
      title: const Text('This face is already enrolled'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'It looks like someone who already has a face on file. The same person should not be enrolled twice.',
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 12),
            for (final match in widget.matches)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(
                  '${match.name} (${match.employeeId}) — ${(match.similarity * 100).round()}% similar',
                  style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
            const SizedBox(height: 12),
            TextField(
              controller: _reason,
              maxLength: 200,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(labelText: 'Reason for enrolling anyway'),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        ValueListenableBuilder<TextEditingValue>(
          valueListenable: _reason,
          builder: (context, value, _) => FilledButton(
            onPressed: value.text.trim().isEmpty ? null : () => Navigator.pop(context, value.text.trim()),
            child: const Text('Enrol anyway'),
          ),
        ),
      ],
    );
  }
}
