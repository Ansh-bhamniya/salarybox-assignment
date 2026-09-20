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
import '../../screen/onboarding/onboarding_screen.dart';
import '../../utils/helpers/onboarding_helper.dart';
import '../../utils/routes.dart';

GoRouter buildRouter() {
  return GoRouter(
    initialLocation: Routes.login,
    refreshListenable: GoRouterRefreshStream(sl<AuthCubit>().stream),
    redirect: (context, state) {
      final authState = sl<AuthCubit>().state;
      final loggingIn = state.matchedLocation == Routes.login;
      final onboarding = state.matchedLocation == Routes.onboarding;

      // Session restore from disk hasn't finished yet — don't bounce to
      // login and cause a flash before we know the real answer.
      if (authState.status == AuthStatus.unknown) return null;

      if (authState.status != AuthStatus.authenticated) {
        if (onboarding) return null;
        // First run: the intro comes before anything else.
        if (!OnboardingHelper.seen) return Routes.onboarding;
        return loggingIn ? null : Routes.login;
      }

      final role = authState.session!.role;
      if (loggingIn || onboarding) {
        return role == UserRole.admin ? Routes.staff : Routes.home;
      }

      final location = state.matchedLocation;
      final onAdminRoute = location.startsWith(Routes.staff);
      final onStaffRoute = location == Routes.home || location == Routes.attendance;
      if (role == UserRole.staff && onAdminRoute) return Routes.home;
      if (role == UserRole.admin && onStaffRoute) return Routes.staff;

      return null;
    },
    routes: [
      GoRoute(path: Routes.onboarding, builder: (context, state) => const OnboardingScreen()),
      GoRoute(path: Routes.login, builder: (context, state) => const LoginScreen()),
      // Admin. Listed most specific first: '/staff/add' must win over '/staff/:id'.
      GoRoute(path: Routes.staff, builder: (context, state) => const StaffListScreen()),
      GoRoute(path: Routes.addStaff, builder: (context, state) => const AddStaffScreen()),
      GoRoute(
        path: Routes.staffProfile,
        builder: (context, state) => StaffProfileScreen(staffId: state.pathParameters[Routes.idParam]!),
      ),
      GoRoute(
        path: Routes.enrol,
        builder: (context, state) => FaceEnrolmentScreen(
          staffId: state.pathParameters[Routes.idParam]!,
          staffName: (state.extra as String?) ?? '',
        ),
      ),
      // Staff land on their profile; the camera is a page pushed from it.
      GoRoute(path: Routes.home, builder: (context, state) => const StaffHomeScreen()),
      GoRoute(path: Routes.attendance, builder: (context, state) => const MarkAttendanceScreen()),
    ],
  );
}
