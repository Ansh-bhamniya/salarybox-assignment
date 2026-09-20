import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:get_it/get_it.dart';
import '../../bloc/mark_attendance/mark_attendance_cubit.dart';
import '../../bloc/staff_home/staff_home_cubit.dart';
import '../../services/attendance_service.dart';
import '../../bloc/auth/auth_cubit.dart';
import '../../services/auth_service.dart';
import '../../bloc/face_capture/face_capture_cubit.dart';
import '../../services/face_embedding_service.dart';
import '../../bloc/add_staff/add_staff_cubit.dart';
import '../../bloc/face_enrolment/face_enrolment_cubit.dart';
import '../../bloc/staff_list/staff_list_cubit.dart';
import '../../bloc/staff_profile/staff_profile_cubit.dart';
import '../../services/staff_service.dart';
import '../../services/camera_capture_controller.dart';
import '../../utils/http/api_client.dart';
import '../../utils/helpers/secure_storage.dart';

final sl = GetIt.instance;

/// Registration order matters: each layer only depends on ones registered
/// before it (core → data → cubits), matching the dependency direction
/// described in ARCHITECTURE.md.
void setupServiceLocator() {
  // core
  sl.registerLazySingleton<FlutterSecureStorage>(() => const FlutterSecureStorage());
  sl.registerLazySingleton<SecureStorage>(() => SecureStorage(sl()));
  sl.registerLazySingleton<ApiClient>(() => ApiClient());

  // auth — AuthCubit is a singleton because it holds app-wide session state
  // read by the router guard from anywhere in the widget tree.
  sl.registerLazySingleton<AuthService>(() => AuthService(sl(), sl()));
  sl.registerLazySingleton<AuthCubit>(() => AuthCubit(sl()));

  // staff
  sl.registerLazySingleton<StaffService>(() => StaffService(sl()));
  sl.registerFactory<StaffListCubit>(() => StaffListCubit(sl()));
  sl.registerFactory<AddStaffCubit>(() => AddStaffCubit(sl()));
  sl.registerFactory<FaceEnrolmentCubit>(() => FaceEnrolmentCubit(sl()));
  sl.registerFactoryParam<StaffProfileCubit, String, void>(
    (staffId, _) => StaffProfileCubit(sl(), staffId),
  );

  // face — FaceEmbeddingService is a singleton (one ML Kit detector for the
  // app's lifetime); CameraCaptureController is a factory since a fresh
  // camera session is needed every time a capture screen is opened.
  sl.registerLazySingleton<FaceEmbeddingService>(() => FaceEmbeddingService());
  sl.registerFactory<CameraCaptureController>(() => CameraCaptureController());
  sl.registerFactory<FaceCaptureCubit>(() => FaceCaptureCubit(sl(), sl()));

  // attendance
  sl.registerFactoryParam<StaffHomeCubit, String, void>(
    (staffId, _) => StaffHomeCubit(sl(), staffId),
  );
  sl.registerLazySingleton<AttendanceService>(() => AttendanceService(sl()));
  sl.registerFactoryParam<MarkAttendanceCubit, String, void>(
    (staffId, _) => MarkAttendanceCubit(
      staffId: staffId,
      camera: sl<CameraCaptureController>(),
      embeddingService: sl(),
      staffService: sl(),
      attendanceService: sl(),
    ),
  );
}
