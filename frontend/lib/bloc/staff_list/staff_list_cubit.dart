import 'package:flutter_bloc/flutter_bloc.dart';
import '../../utils/http/api_exception.dart';
import '../../services/staff_service.dart';
import './staff_list_state.dart';

class StaffListCubit extends Cubit<StaffListState> {
  StaffListCubit(this._service) : super(const StaffListState.loading()) {
    load();
  }

  final StaffService _service;

  Future<void> load() async {
    emit(const StaffListState.loading());
    try {
      final staff = await _service.list();
      emit(StaffListState(status: StaffListStatus.loaded, staff: staff));
    } on ApiException catch (e) {
      emit(StaffListState(status: StaffListStatus.error, errorMessage: e.message));
    }
  }
}
