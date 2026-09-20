import 'package:equatable/equatable.dart';
import '../../models/staff.dart';
import '../../models/attendance_record.dart';

enum StaffHomeStatus { loading, loaded, error }

class StaffHomeState extends Equatable {
  const StaffHomeState({required this.status, this.staff, this.attendance = const [], this.errorMessage});

  const StaffHomeState.loading() : this(status: StaffHomeStatus.loading);

  final StaffHomeStatus status;
  final Staff? staff;

  /// The staff member's own attendance, newest first.
  final List<AttendanceRecord> attendance;
  final String? errorMessage;

  /// Today's check-in (local calendar day), if there is one.
  AttendanceRecord? get today {
    final now = DateTime.now();
    for (final record in attendance) {
      final t = record.timestamp;
      if (t.year == now.year && t.month == now.month && t.day == now.day) return record;
    }
    return null;
  }

  @override
  List<Object?> get props => [status, staff, attendance, errorMessage];
}
