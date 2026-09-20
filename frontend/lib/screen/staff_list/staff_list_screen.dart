import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import '../../utils/routes.dart';
import '../../config/di/service_locator.dart';
import '../../widgets/app_logo.dart';
import '../../widgets/content_width.dart';
import '../../widgets/error_view.dart';
import '../../widgets/status_chip.dart';
import '../../bloc/auth/auth_cubit.dart';
import '../../widgets/theme_toggle.dart';
import '../../bloc/staff_list/staff_list_cubit.dart';
import '../../bloc/staff_list/staff_list_state.dart';
import '../../models/staff.dart';
import '../../widgets/staff_avatar.dart';
import '../../config/theme/app_spacing.dart';
import '../../config/theme/app_theme.dart';
import '../../config/theme/app_icons.dart';
import '../../widgets/app_fab.dart';

class StaffListScreen extends StatelessWidget {
  const StaffListScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => sl<StaffListCubit>(),
      child: Scaffold(
        appBar: AppBar(
          title: const AppLogo(height: 30),
          actions: [
            const ThemeToggleButton(),
            IconButton(
              tooltip: 'Log out',
              icon: const Icon(AppIcons.logout),
              onPressed: () => context.read<AuthCubit>().logout(),
            ),
          ],
        ),
        body: BlocBuilder<StaffListCubit, StaffListState>(
          builder: (context, state) {
            switch (state.status) {
              case StaffListStatus.loading:
                return const Center(child: CircularProgressIndicator());
              case StaffListStatus.error:
                return ErrorView(
                  message: state.errorMessage ?? 'Failed to load staff',
                  onRetry: () => context.read<StaffListCubit>().load(),
                );
              case StaffListStatus.loaded:
                if (state.staff.isEmpty) {
                  return _EmptyState(onAdd: () => _openAddStaff(context));
                }
                return _StaffList(staff: state.staff);
            }
          },
        ),
        // Builder: this button's own context must sit *below* the
        // BlocProvider above, or read<StaffListCubit>() can't find it.
        floatingActionButton: Builder(
          builder: (context) =>
              AppFab(icon: AppIcons.add, tooltip: 'Add staff', onPressed: () => _openAddStaff(context)),
        ),
      ),
    );
  }
}

Future<void> _openAddStaff(BuildContext context) async {
  final cubit = context.read<StaffListCubit>();
  final router = GoRouter.of(context);

  final added = await router.push<Staff>(Routes.addStaff);
  cubit.load(); // the new staff shows up straight away
  if (added == null) return;

  await router.push(Routes.enrolOf(added.id), extra: added.name);
  cubit.load(); // enrolling changes its status
}

class _StaffList extends StatelessWidget {
  const _StaffList({required this.staff});

  final List<Staff> staff;

  @override
  Widget build(BuildContext context) {
    final enrolled = staff.where((s) => s.isEnrolled).length;
    final pending = staff.length - enrolled;
    final theme = Theme.of(context);

    return ContentWidth(
      child: RefreshIndicator(
        onRefresh: () => context.read<StaffListCubit>().load(),
        child: ListView.separated(
          // Extra bottom padding so the last row clears the floating button.
          padding: AppSpacing.pageWithFab,
          itemCount: staff.length + 1,
          separatorBuilder: (_, _) => const SizedBox(height: 8),
          itemBuilder: (context, index) {
            if (index == 0) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 8, left: 4),
                child: Text(
                  pending == 0
                      ? '${staff.length} staff • all enrolled'
                      : '${staff.length} staff • $pending need${pending == 1 ? 's' : ''} face enrolment',
                  style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
              );
            }
            return _StaffCard(staff: staff[index - 1]);
          },
        ),
      ),
    );
  }
}

class _StaffCard extends StatelessWidget {
  const _StaffCard({required this.staff});

  final Staff staff;

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () async {
          await context.push(Routes.staffProfileOf(staff.id));
          // Enrolling from the profile changes this row's status.
          if (context.mounted) context.read<StaffListCubit>().load();
        },
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              StaffAvatar(name: staff.name, photoUrl: staff.enrollmentPhotoUrl),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      staff.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'ID: ${staff.employeeId}',
                      style: Theme.of(
                        context,
                      ).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              staff.isEnrolled
                  ? StatusChip(
                      label: 'Enrolled',
                      icon: AppIcons.checkFilled,
                      color: Theme.of(context).colorScheme.onSurface,
                    )
                  : StatusChip(
                      label: 'Enrol face',
                      icon: AppIcons.warning,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.onAdd});

  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.messageInset),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 96,
              height: 96,
              decoration: BoxDecoration(shape: BoxShape.circle, color: theme.colorScheme.primaryContainer),
              child: Icon(AppIcons.people, size: 48, color: theme.colorScheme.onPrimaryContainer),
            ),
            const SizedBox(height: 24),
            Text('No staff yet', style: AppTheme.display(context, size: 26)),
            const SizedBox(height: 8),
            Text(
              'Add your first staff member, then enrol their face so they can mark attendance.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(onPressed: onAdd, icon: const Icon(AppIcons.addStaff), label: const Text('Add staff')),
          ],
        ),
      ),
    );
  }
}
