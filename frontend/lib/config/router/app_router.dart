import 'package:go_router/go_router.dart';
import '../../screen/mark_attendance/mark_attendance_screen.dart';
import '../../screen/staff_home/staff_home_screen.dart';
import '../../bloc/auth/auth_cubit.dart';
import '../../bloc/auth/auth_state.dart';
import '../../models/session.dart';
import '../../screen/login/login_screen.dart';
import '../../screen/face_enrolment/face_enrolment_screen.dart';
import '../../screen/add_staff/add_staff_screen.dart';
import '../../screen/staff_list/staff_list_screen.dart';
import '../../screen/staff_profile/staff_profile_screen.dart';
import '../di/service_locator.dart';
import '../../utils/go_router_refresh_stream.dart';

GoRouter buildRouter() {
  return GoRouter(
    initialLocation: '/login',
    refreshListenable: GoRouterRefreshStream(sl<AuthCubit>().stream),
    redirect: (context, state) {
      final authState = sl<AuthCubit>().state;
      final loggingIn = state.matchedLocation == '/login';

      // Session restore from disk hasn't finished yet — don't bounce to
      // login and cause a flash before we know the real answer.
      if (authState.status == AuthStatus.unknown) return null;

      if (authState.status != AuthStatus.authenticated) {
        return loggingIn ? null : '/login';
      }

      final role = authState.session!.role;
      if (loggingIn) {
        return role == UserRole.admin ? '/staff' : '/home';
      }

      final location = state.matchedLocation;
      final onAdminRoute = location.startsWith('/staff');
      final onStaffRoute = location == '/home' || location == '/attendance';
      if (role == UserRole.staff && onAdminRoute) return '/home';
      if (role == UserRole.admin && onStaffRoute) return '/staff';

      return null;
    },
    routes: [
      GoRoute(path: '/login', builder: (context, state) => const LoginScreen()),
      GoRoute(
        path: '/staff',
        builder: (context, state) => const StaffListScreen(),
        routes: [
          GoRoute(path: 'add', builder: (context, state) => const AddStaffScreen()),
          GoRoute(
            path: ':id',
            builder: (context, state) => StaffProfileScreen(staffId: state.pathParameters['id']!),
            routes: [
              GoRoute(
                path: 'enroll',
                builder: (context, state) => FaceEnrolmentScreen(
                  staffId: state.pathParameters['id']!,
                  staffName: (state.extra as String?) ?? '',
                ),
              ),
            ],
          ),
        ],
      ),
      // Staff land on their profile; the camera is a page pushed from it.
      GoRoute(path: '/home', builder: (context, state) => const StaffHomeScreen()),
      GoRoute(path: '/attendance', builder: (context, state) => const MarkAttendanceScreen()),
    ],
  );
}
