import 'package:flutter_bloc/flutter_bloc.dart';
import '../../utils/http/api_exception.dart';
import '../../services/staff_service.dart';
import './add_staff_state.dart';

class AddStaffCubit extends Cubit<AddStaffState> {
  AddStaffCubit(this._service) : super(const AddStaffState());

  final StaffService _service;

  Future<void> submit({required String name, required String employeeId}) async {
    emit(const AddStaffState(status: AddStaffStatus.submitting));
    try {
      final staff = await _service.create(name: name, employeeId: employeeId);
      emit(AddStaffState(status: AddStaffStatus.success, staff: staff));
    } on ApiException catch (e) {
      emit(AddStaffState(status: AddStaffStatus.error, errorMessage: e.message));
    }
  }
}
