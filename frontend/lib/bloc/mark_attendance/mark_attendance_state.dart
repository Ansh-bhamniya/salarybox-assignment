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

  /// Too many failures in a row; the person is told to ask their admin.
  lockedOut,

  success,
  error,
}

class MarkAttendanceState extends Equatable {
  const MarkAttendanceState({
    this.status = MarkAttendanceStatus.initial,
    this.similarity,
    this.errorMessage,
    this.failedAttempts = 0,
  });

  final MarkAttendanceStatus status;
  final double? similarity;
  final String? errorMessage;

  /// Failed checks in a row on this screen; a success (or leaving) starts again at zero.
  final int failedAttempts;

  @override
  List<Object?> get props => [status, similarity, errorMessage, failedAttempts];
}
