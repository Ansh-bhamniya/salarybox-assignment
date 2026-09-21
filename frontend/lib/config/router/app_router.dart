import 'package:flutter/foundation.dart';
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
import '../../screen/splash/splash_screen.dart';
import '../../screen/liveness_debug/liveness_debug_screen.dart';
import '../env.dart';
import '../../utils/helpers/onboarding_helper.dart';
import '../../utils/routes.dart';

GoRouter buildRouter() {
  // Flips once the splash has been on screen for its full duration.
  final splashDone = ValueNotifier<bool>(false);

  return GoRouter(
    // A build made for tuning the head-turn check opens straight into its debug screen.
    initialLocation: Env.livenessDebug ? Routes.livenessDebug : Routes.splash,
    refreshListenable: Listenable.merge([GoRouterRefreshStream(sl<AuthCubit>().stream), splashDone]),
    redirect: (context, state) {
      final authState = sl<AuthCubit>().state;
      final onSplash = state.matchedLocation == Routes.splash;
      final loggingIn = state.matchedLocation == Routes.login;
      final onboarding = state.matchedLocation == Routes.onboarding;

      // The tuning screen is reachable signed out, and only in builds that ask for it.
      if (Env.livenessDebug && state.matchedLocation == Routes.livenessDebug) return null;

      // Stay on the splash until its time is up.
      if (onSplash && !splashDone.value) return null;

      // Session restore from disk hasn't finished yet — don't bounce to
      // login and cause a flash before we know the real answer. (This also
      // keeps the splash up if the restore outlasts it.)
      if (authState.status == AuthStatus.unknown) return null;

      if (authState.status != AuthStatus.authenticated) {
        if (onboarding) return null;
        // First run: the intro comes before anything else.
        if (!OnboardingHelper.seen) return Routes.onboarding;
        return loggingIn ? null : Routes.login;
      }

      final role = authState.session!.role;
      if (onSplash || loggingIn || onboarding) {
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
      GoRoute(
        path: Routes.splash,
        builder: (context, state) => SplashScreen(onFinished: () => splashDone.value = true),
      ),
      if (Env.livenessDebug)
        GoRoute(path: Routes.livenessDebug, builder: (context, state) => const LivenessDebugScreen()),
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
          isReEnrol: state.uri.queryParameters[Routes.reEnrolParam] == 'true',
        ),
      ),
      // Staff land on their profile; the camera is a page pushed from it.
      GoRoute(path: Routes.home, builder: (context, state) => const StaffHomeScreen()),
      GoRoute(path: Routes.attendance, builder: (context, state) => const MarkAttendanceScreen()),
    ],
  );
}
