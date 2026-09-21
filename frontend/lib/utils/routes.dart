/// Every screen route in the app, in one place. Navigate with these
/// (`context.push(Routes.login)`) and declare the router from them, so a path
/// is only ever spelled once.
///
/// Backend endpoints are a different thing and live in the services.
abstract final class Routes {
  // Before login
  static const splash = '/splash';
  static const livenessDebug = '/liveness-debug';
  static const onboarding = '/onboarding';
  static const login = '/login';

  // Staff
  static const home = '/home';
  static const attendance = '/attendance';

  // Admin
  static const staff = '/staff';
  static const addStaff = '/staff/add';
  static const staffProfile = '/staff/:$idParam';
  static const enrol = '/staff/:$idParam/enroll';

  /// The `:id` segment of [staffProfile] and [enrol].
  static const idParam = 'id';

  /// The concrete path for one staff member's profile.
  static String staffProfileOf(String id) => '/staff/$id';

  /// The concrete path for enrolling one staff member's face. [reEnrol] marks
  /// replacing an existing enrolment, which asks for a reason.
  static String enrolOf(String id, {bool reEnrol = false}) =>
      reEnrol ? '/staff/$id/enroll?$reEnrolParam=true' : '/staff/$id/enroll';

  /// Query parameter that marks an enrolment as a re-enrolment.
  static const reEnrolParam = 'reenrol';
}
