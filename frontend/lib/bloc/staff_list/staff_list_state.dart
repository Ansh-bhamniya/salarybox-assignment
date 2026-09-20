import 'package:equatable/equatable.dart';
import '../../models/staff.dart';

enum StaffListStatus { loading, loaded, error }

class StaffListState extends Equatable {
  const StaffListState({required this.status, this.staff = const [], this.errorMessage});

  const StaffListState.loading() : this(status: StaffListStatus.loading);

  final StaffListStatus status;
  final List<Staff> staff;
  final String? errorMessage;

  @override
  List<Object?> get props => [status, staff, errorMessage];
}
