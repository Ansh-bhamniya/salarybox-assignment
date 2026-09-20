import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../utils/http/api_exception.dart';
import '../../services/staff_service.dart';
import '../../models/attendance_record.dart';
import './staff_home_state.dart';

/// Loads the logged-in staff member's own profile and attendance history
/// for the home screen: who they are, whether their face is enrolled (which
/// decides if they can mark attendance yet), and what they've marked.
class StaffHomeCubit extends Cubit<StaffHomeState> {
  StaffHomeCubit(this._service, this._staffId) : super(const StaffHomeState.loading()) {
    load();
  }

  final StaffService _service;
  final String _staffId;

  Future<void> load() async {
    // Pull-to-refresh keeps showing the current screen instead of
    // flashing a spinner over it.
    if (state.staff == null) emit(const StaffHomeState.loading());

    final staffFuture = _service.getById(_staffId);
    // History is a nice-to-have: if it fails the profile still shows.
    final historyFuture = _service
        .attendanceHistory(_staffId)
        .then<List<AttendanceRecord>>((records) => records, onError: (_) => state.attendance);

    try {
      final staff = await staffFuture;
      final history = await historyFuture;
      emit(StaffHomeState(status: StaffHomeStatus.loaded, staff: staff, attendance: history));
    } on ApiException catch (e) {
      debugPrint('[staff-home] load failed: ${e.message}');
      if (state.staff != null) return; // a failed refresh shouldn't wipe a good screen
      emit(StaffHomeState(status: StaffHomeStatus.error, errorMessage: e.message));
    }
  }
}
