import 'package:equatable/equatable.dart';

enum FaceEnrolmentSubmitStatus { idle, submitting, success, error }

class FaceEnrolmentSubmitState extends Equatable {
  const FaceEnrolmentSubmitState({this.status = FaceEnrolmentSubmitStatus.idle, this.errorMessage});

  final FaceEnrolmentSubmitStatus status;
  final String? errorMessage;

  @override
  List<Object?> get props => [status, errorMessage];
}
