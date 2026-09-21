import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import '../../utils/routes.dart';
import '../../config/di/service_locator.dart';
import '../../widgets/content_width.dart';
import '../../widgets/error_view.dart';
import '../../widgets/status_chip.dart';
import '../../models/attendance_record.dart';
import '../../bloc/staff_profile/staff_profile_cubit.dart';
import '../../bloc/staff_profile/staff_profile_state.dart';
import '../../widgets/staff_avatar.dart';
import '../../config/theme/app_spacing.dart';
import '../../config/theme/app_theme.dart';
import '../../widgets/section_title.dart';
import '../../config/theme/app_radius.dart';
import '../../config/theme/app_icons.dart';
import '../../widgets/app_back_button.dart';
import '../../widgets/loading_overlay.dart';
import './delete_staff_dialog.dart';

class StaffProfileScreen extends StatelessWidget {
  const StaffProfileScreen({super.key, required this.staffId});

  final String staffId;

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => sl<StaffProfileCubit>(param1: staffId),
      child: _StaffProfileView(staffId: staffId),
    );
  }
}

class _StaffProfileView extends StatelessWidget {
  const _StaffProfileView({required this.staffId});

  final String staffId;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: const AppBackButton(),
        leadingWidth: AppBackButton.leadingWidth,
        title: const Text('Staff profile'),
      ),
      body: BlocBuilder<StaffProfileCubit, StaffProfileState>(
        builder: (context, state) {
          switch (state.status) {
            case StaffProfileStatus.loading:
              return const Center(child: CircularProgressIndicator());
            case StaffProfileStatus.error:
              return ErrorView(
                message: state.errorMessage ?? 'Failed to load profile',
                onRetry: () => context.read<StaffProfileCubit>().load(),
              );
            case StaffProfileStatus.loaded:
              final staff = state.staff!;
              final theme = Theme.of(context);
              return Stack(
                children: [
                  ContentWidth(
                    child: RefreshIndicator(
                      onRefresh: () => context.read<StaffProfileCubit>().load(),
                      child: ListView(
                        padding: AppSpacing.page,
                        children: [
                          Card(
                            child: Padding(
                              padding: const EdgeInsets.all(24),
                              child: Column(
                                children: [
                                  StaffAvatar(name: staff.name, photoUrl: staff.enrollmentPhotoUrl, radius: 48),
                                  const SizedBox(height: 16),
                                  Text(staff.name, style: AppTheme.display(context, size: 26)),
                                  const SizedBox(height: 4),
                                  Text(
                                    'ID: ${staff.employeeId}',
                                    style: theme.textTheme.bodyMedium?.copyWith(
                                      color: theme.colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                                  const SizedBox(height: 12),
                                  staff.isEnrolled
                                      ? StatusChip(
                                          label: 'Face enrolled',
                                          icon: AppIcons.checkFilled,
                                          color: theme.colorScheme.onSurface,
                                        )
                                      : StatusChip(
                                          label: 'Face not enrolled',
                                          icon: AppIcons.warning,
                                          color: theme.colorScheme.onSurfaceVariant,
                                        ),
                                  const SizedBox(height: 24),
                                  SizedBox(
                                    width: double.infinity,
                                    child: staff.isEnrolled
                                        ? FilledButton.icon(
                                            icon: const Icon(AppIcons.refresh),
                                            label: const Text('Re-enrol face'),
                                            onPressed: () =>
                                                context.push(Routes.enrolOf(staffId, reEnrol: true), extra: staff.name),
                                          )
                                        : FilledButton.icon(
                                            icon: const Icon(AppIcons.face),
                                            label: const Text('Enrol face'),
                                            onPressed: () => context.push(Routes.enrolOf(staffId), extra: staff.name),
                                          ),
                                  ),
                                  const SizedBox(height: 12),
                                  SizedBox(
                                    width: double.infinity,
                                    child: TextButton.icon(
                                      icon: const Icon(AppIcons.delete),
                                      label: const Text('Delete staff'),
                                      style: TextButton.styleFrom(foregroundColor: theme.colorScheme.error),
                                      onPressed: state.deleting ? null : () => _delete(context, state),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 24),
                          const SectionTitle('Attendance history'),
                          if (state.attendance.isEmpty)
                            const _NoAttendance()
                          else
                            for (final record in state.attendance) ...[
                              _AttendanceTile(record: record),
                              const SizedBox(height: 8),
                            ],
                        ],
                      ),
                    ),
                  ),
                  LoadingOverlay(visible: state.deleting, message: 'Deleting…'),
                ],
              );
          }
        },
      ),
    );
  }

  Future<void> _delete(BuildContext context, StaffProfileState state) async {
    final staff = state.staff!;
    final cubit = context.read<StaffProfileCubit>();
    final messenger = ScaffoldMessenger.of(context);
    final router = GoRouter.of(context);

    final confirmed = await confirmDeleteStaff(context, name: staff.name, attendanceRecords: state.attendance.length);
    if (!confirmed) return;

    final problem = await cubit.delete();
    messenger.hideCurrentSnackBar();
    if (problem != null) {
      messenger.showSnackBar(SnackBar(content: Text(problem)));
      return;
    }
    messenger.showSnackBar(SnackBar(content: Text('${staff.name} was deleted')));
    if (router.canPop()) router.pop();
  }
}

class _NoAttendance extends StatelessWidget {
  const _NoAttendance();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            Icon(AppIcons.noEvents, size: 32, color: theme.colorScheme.onSurfaceVariant),
            const SizedBox(height: 8),
            Text(
              'No attendance recorded yet',
              style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}

class _AttendanceTile extends StatelessWidget {
  const _AttendanceTile({required this.record});

  final AttendanceRecord record;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _showSelfie(context),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: AppRadius.tileBorder,
                child: SizedBox(width: 56, height: 56, child: _SelfieImage(url: record.selfieUrl)),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${record.date} • ${record.time}',
                      style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Icon(AppIcons.place, size: 14, color: theme.colorScheme.onSurfaceVariant),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            '${record.latitude.toStringAsFixed(5)}, ${record.longitude.toStringAsFixed(5)}',
                            style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showSelfie(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (_) => Dialog(
        clipBehavior: Clip.antiAlias,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: InteractiveViewer(
                child: _SelfieImage(url: record.selfieUrl, fit: BoxFit.contain),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                '${record.date} • ${record.time}',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SelfieImage extends StatelessWidget {
  const _SelfieImage({required this.url, this.fit = BoxFit.cover});

  final String url;
  final BoxFit fit;

  @override
  Widget build(BuildContext context) {
    return Image.network(
      url,
      fit: fit,
      loadingBuilder: (context, child, progress) =>
          progress == null ? child : const Center(child: CircularProgressIndicator(strokeWidth: 2)),
      errorBuilder: (context, error, stackTrace) => ColoredBox(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        child: const Icon(AppIcons.brokenImage),
      ),
    );
  }
}
