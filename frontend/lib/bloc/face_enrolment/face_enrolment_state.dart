import 'package:equatable/equatable.dart';
import '../../models/duplicate_match.dart';

enum FaceEnrolmentSubmitStatus { idle, submitting, success, error, duplicateFound }

class FaceEnrolmentSubmitState extends Equatable {
  const FaceEnrolmentSubmitState({
    this.status = FaceEnrolmentSubmitStatus.idle,
    this.errorMessage,
    this.duplicates = const [],
  });

  final FaceEnrolmentSubmitStatus status;
  final String? errorMessage;

  /// Who the face looks like, when [status] is [FaceEnrolmentSubmitStatus.duplicateFound].
  final List<DuplicateMatch> duplicates;

  @override
  List<Object?> get props => [status, errorMessage, duplicates.map((d) => d.employeeId).toList()];
}
