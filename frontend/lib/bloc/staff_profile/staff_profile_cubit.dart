import 'package:flutter_bloc/flutter_bloc.dart';
import '../../utils/http/api_exception.dart';
import '../../services/staff_service.dart';
import './staff_profile_state.dart';

class StaffProfileCubit extends Cubit<StaffProfileState> {
  StaffProfileCubit(this._service, this.staffId) : super(const StaffProfileState.loading()) {
    load();
  }

  final StaffService _service;
  final String staffId;

  Future<void> load() async {
    emit(const StaffProfileState.loading());
    try {
      final staff = await _service.getById(staffId);
      final attendance = await _service.attendanceHistory(staffId);
      emit(StaffProfileState(status: StaffProfileStatus.loaded, staff: staff, attendance: attendance));
    } on ApiException catch (e) {
      emit(StaffProfileState(status: StaffProfileStatus.error, errorMessage: e.message));
    }
  }

  /// Deletes this staff member for good. Returns null once it is done, or a message
  /// for the admin if it could not be (the profile stays as it was).
  Future<String?> delete() async {
    if (state.deleting) return null;
    emit(StaffProfileState(status: state.status, staff: state.staff, attendance: state.attendance, deleting: true));
    try {
      await _service.delete(staffId);
      return null;
    } on ApiException catch (e) {
      if (!isClosed) {
        emit(StaffProfileState(status: state.status, staff: state.staff, attendance: state.attendance));
      }
      return e.message;
    }
  }
}
