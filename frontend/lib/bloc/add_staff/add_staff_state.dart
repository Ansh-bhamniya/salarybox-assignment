import 'package:equatable/equatable.dart';
import '../../models/staff.dart';

enum AddStaffStatus { idle, submitting, success, error }

class AddStaffState extends Equatable {
  const AddStaffState({this.status = AddStaffStatus.idle, this.staff, this.errorMessage});

  final AddStaffStatus status;
  final Staff? staff;
  final String? errorMessage;

  @override
  List<Object?> get props => [status, staff?.id, errorMessage];
}
