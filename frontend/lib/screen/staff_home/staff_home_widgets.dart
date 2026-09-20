import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../config/theme/app_spacing.dart';
import '../../config/theme/app_theme.dart';
import '../../models/staff.dart';
import '../../widgets/staff_avatar.dart';
import '../../widgets/theme_toggle.dart';
import '../../models/attendance_record.dart';
import '../../config/theme/app_radius.dart';
import '../../config/theme/app_icons.dart';

/// The staff member's avatar as a button (top right). Tapping it opens a
/// small sheet with who they are, the dark-mode switch and log out.
class ProfileButton extends StatelessWidget {
  const ProfileButton({super.key, required this.staff, required this.onLogout});

  final Staff staff;
  final VoidCallback onLogout;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Tooltip(
      message: 'Profile',
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: () => _showProfileSheet(context, staff, onLogout),
        child: Container(
          padding: const EdgeInsets.all(2),
          decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: scheme.outlineVariant, width: 1.5)),
          child: StaffAvatar(name: staff.name, photoUrl: staff.enrollmentPhotoUrl, radius: 24),
        ),
      ),
    );
  }
}

Future<void> _showProfileSheet(BuildContext context, Staff staff, VoidCallback onLogout) {
  return showModalBottomSheet<void>(
    context: context,
    builder: (sheetContext) {
      final theme = Theme.of(sheetContext);
      final scheme = theme.colorScheme;
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  StaffAvatar(name: staff.name, photoUrl: staff.enrollmentPhotoUrl, radius: 28),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          staff.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'ID ${staff.employeeId}',
                          style: theme.textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              const Divider(),
              const ThemeSwitchTile(),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: scheme.outlineVariant)),
                  child: Icon(AppIcons.logout, size: 20, color: scheme.onSurface),
                ),
                title: Text('Log out', style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  onLogout();
                },
              ),
            ],
          ),
        ),
      );
    },
  );
}

/// Small pill that shows the employee ID under the name.
class IdPill extends StatelessWidget {
  const IdPill({super.key, required this.employeeId});

  final String employeeId;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(color: scheme.primaryContainer, borderRadius: AppRadius.pillBorder),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(AppIcons.idBadge, size: 16, color: scheme.onPrimaryContainer),
          const SizedBox(width: 6),
          Text(
            'ID $employeeId',
            style: Theme.of(context)
                .textTheme
                .labelLarge
                ?.copyWith(fontWeight: FontWeight.w700, color: scheme.onPrimaryContainer),
          ),
        ],
      ),
    );
  }
}

/// Today's status in plain words — the one thing a staff member needs to
/// know before deciding whether to tap "Mark attendance".
class StatusCard extends StatelessWidget {
  const StatusCard({super.key, required this.enrolled, this.today});

  final bool enrolled;
  final AttendanceRecord? today;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final muted = theme.textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant, height: 1.4);

    final Widget content;
    if (!enrolled) {
      content = Column(
        key: const ValueKey('not-enrolled'),
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Action needed', style: muted),
          const SizedBox(height: 4),
          Text('Face not enrolled', style: AppTheme.display(context, size: 26)),
          const SizedBox(height: 8),
          Text('Ask your admin to enrol your face. Then pull down to refresh.', style: muted),
        ],
      );
    } else if (today == null) {
      content = Column(
        key: const ValueKey('not-checked-in'),
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Today', style: muted),
          const SizedBox(height: 4),
          Text('Not checked in yet', style: AppTheme.display(context, size: 26)),
          const SizedBox(height: 8),
          Text('Tap Mark attendance to check in.', style: muted),
        ],
      );
    } else {
      content = Column(
        key: const ValueKey('checked-in'),
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(AppIcons.checkFilled, size: 18, color: scheme.onSurface),
              const SizedBox(width: 6),
              Text('Checked in', style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
            ],
          ),
          const SizedBox(height: 8),
          Text(today!.time, style: AppTheme.display(context, size: 48)),
          const SizedBox(height: 8),
          Text('${DateFormat('EEEE, MMM d').format(today!.timestamp)} · Face verified', style: muted),
        ],
      );
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: SizedBox(
          width: double.infinity,
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 300),
            switchInCurve: Curves.easeOutCubic,
            transitionBuilder: (child, animation) => FadeTransition(opacity: animation, child: child),
            child: content,
          ),
        ),
      ),
    );
  }
}

/// One past check-in: a date bubble, the day, and the time.
class ActivityTile extends StatelessWidget {
  const ActivityTile({super.key, required this.record});

  final AttendanceRecord record;

  static String _relativeDay(DateTime timestamp) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(timestamp.year, timestamp.month, timestamp.day);
    final diff = today.difference(day).inDays;
    if (diff == 0) return 'Today';
    if (diff == 1) return 'Yesterday';
    return DateFormat('EEEE, d MMM').format(timestamp);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final ts = record.timestamp;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Container(
              width: 56,
              height: 60,
              decoration: BoxDecoration(color: scheme.primaryContainer, borderRadius: AppRadius.tileBorder),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    DateFormat('d').format(ts),
                    style: theme.textTheme.titleLarge
                        ?.copyWith(fontWeight: FontWeight.w800, height: 1.1, color: scheme.onPrimaryContainer),
                  ),
                  Text(
                    DateFormat('EEE').format(ts).toUpperCase(),
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: scheme.onPrimaryContainer.withValues(alpha: 0.7),
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.6,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(_relativeDay(ts), style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
                  const SizedBox(height: 2),
                  Text(
                    'Checked in at ${record.time}',
                    style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
