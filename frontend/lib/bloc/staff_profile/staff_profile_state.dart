import 'package:equatable/equatable.dart';
import '../../models/attendance_record.dart';
import '../../models/staff.dart';

enum StaffProfileStatus { loading, loaded, error }

class StaffProfileState extends Equatable {
  const StaffProfileState({
    required this.status,
    this.staff,
    this.attendance = const [],
    this.errorMessage,
  });

  const StaffProfileState.loading() : this(status: StaffProfileStatus.loading);

  final StaffProfileStatus status;
  final Staff? staff;
  final List<AttendanceRecord> attendance;
  final String? errorMessage;

  @override
  List<Object?> get props => [status, staff?.id, attendance, errorMessage];
}
