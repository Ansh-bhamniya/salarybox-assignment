import 'package:equatable/equatable.dart';

enum MarkAttendanceStatus { initial, cameraReady, processing, matchFailed, success, error }

class MarkAttendanceState extends Equatable {
  const MarkAttendanceState({
    this.status = MarkAttendanceStatus.initial,
    this.similarity,
    this.errorMessage,
  });

  final MarkAttendanceStatus status;
  final double? similarity;
  final String? errorMessage;

  @override
  List<Object?> get props => [status, similarity, errorMessage];
}
