import 'package:equatable/equatable.dart';

enum MarkAttendanceStatus {
  initial,

  /// The camera is up and the head-turn check is running (or waiting for a face).
  cameraReady,

  /// The check passed and the person is being verified, then recorded.
  processing,

  /// The check passed but the face is not the enrolled person's.
  matchFailed,

  /// The head-turn check itself did not pass; the person can try again.
  livenessFailed,

  success,
  error,
}

class MarkAttendanceState extends Equatable {
  const MarkAttendanceState({this.status = MarkAttendanceStatus.initial, this.similarity, this.errorMessage});

  final MarkAttendanceStatus status;
  final double? similarity;
  final String? errorMessage;

  @override
  List<Object?> get props => [status, similarity, errorMessage];
}
