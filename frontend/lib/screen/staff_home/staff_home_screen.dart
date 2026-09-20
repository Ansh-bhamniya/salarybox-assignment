import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import '../../config/di/service_locator.dart';
import '../../config/theme/app_theme.dart';
import '../../widgets/content_width.dart';
import '../../widgets/error_view.dart';
import '../../bloc/auth/auth_cubit.dart';
import '../../models/staff.dart';
import '../../bloc/staff_home/staff_home_cubit.dart';
import '../../bloc/staff_home/staff_home_state.dart';
import '../../models/attendance_record.dart';
import './staff_home_widgets.dart';
import '../../config/theme/app_spacing.dart';
import '../../widgets/section_title.dart';
import '../../config/theme/app_icons.dart';

/// Where a staff member lands after logging in. Deliberately sparse: who
/// you are, whether you've checked in today, and one obvious button. The
/// camera only opens when they tap it.
class StaffHomeScreen extends StatelessWidget {
  const StaffHomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final session = context.read<AuthCubit>().state.session!;
    return BlocProvider(
      create: (_) => sl<StaffHomeCubit>(param1: session.staffId!),
      child: const _StaffHomeView(),
    );
  }
}

class _StaffHomeView extends StatelessWidget {
  const _StaffHomeView();

  Future<void> _markAttendance(BuildContext context) async {
    final cubit = context.read<StaffHomeCubit>();
    final marked = await context.push<bool>('/attendance');
    cubit.load(); // pick up the new check-in either way
    if (marked == true && context.mounted) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(content: Text('Attendance recorded')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: BlocBuilder<StaffHomeCubit, StaffHomeState>(
          builder: (context, state) {
            switch (state.status) {
              case StaffHomeStatus.loading:
                return const Center(child: CircularProgressIndicator());
              case StaffHomeStatus.error:
                return ErrorView(
                  message: state.errorMessage ?? 'Failed to load your profile',
                  onRetry: () => context.read<StaffHomeCubit>().load(),
                );
              case StaffHomeStatus.loaded:
                return StaffHomeContent(
                  staff: state.staff!,
                  attendance: state.attendance,
                  today: state.today,
                  onRefresh: () => context.read<StaffHomeCubit>().load(),
                  onMarkAttendance: () => _markAttendance(context),
                  onLogout: () => context.read<AuthCubit>().logout(),
                );
            }
          },
        ),
      ),
    );
  }
}

/// The staff home layout, separate from the cubit so it can be rendered
/// with plain data.
class StaffHomeContent extends StatelessWidget {
  const StaffHomeContent({
    super.key,
    required this.staff,
    required this.attendance,
    required this.today,
    required this.onRefresh,
    required this.onMarkAttendance,
    required this.onLogout,
  });

  final Staff staff;
  final List<AttendanceRecord> attendance;
  final AttendanceRecord? today;
  final Future<void> Function() onRefresh;
  final VoidCallback onMarkAttendance;
  final VoidCallback onLogout;

  static String _greeting() {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Good morning,';
    if (hour < 17) return 'Good afternoon,';
    return 'Good evening,';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final firstName = staff.name.trim().split(' ').first;
    final recent = attendance.take(3).toList();
    final checkedInToday = today != null;

    final markLabel = checkedInToday ? 'Mark again' : 'Mark attendance';
    final canMark = staff.isEnrolled;

    return ContentWidth(
      child: Column(
        children: [
          Expanded(
            child: RefreshIndicator(
              onRefresh: onRefresh,
              child: ListView(
                padding: AppSpacing.page,
                children: [
                  // Greeting, name and ID on the left; profile button top right.
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.only(left: 4, top: 4),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _greeting(),
                                style: theme.textTheme.titleMedium?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                firstName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: AppTheme.display(context, size: 40),
                              ),
                              const SizedBox(height: 12),
                              IdPill(employeeId: staff.employeeId),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      ProfileButton(staff: staff, onLogout: onLogout),
                    ],
                  ),
                  const SizedBox(height: 28),

                  StatusCard(enrolled: staff.isEnrolled, today: today),

                  if (recent.isNotEmpty) ...[
                    const SizedBox(height: AppSpacing.section),
                    const SectionTitle('Recent activity'),
                    for (final record in recent) ...[
                      ActivityTile(record: record),
                      const SizedBox(height: 8),
                    ],
                  ],
                ],
              ),
            ),
          ),

          // The one thing to tap, pinned at the bottom in thumb reach — always
          // the solid accent purple (grey only while it can't be used yet).
          SafeArea(
            top: false,
            child: Padding(
              padding: AppSpacing.bottomBar,
              child: SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  icon: const Icon(AppIcons.camera),
                  label: Text(markLabel),
                  onPressed: canMark ? onMarkAttendance : null,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
