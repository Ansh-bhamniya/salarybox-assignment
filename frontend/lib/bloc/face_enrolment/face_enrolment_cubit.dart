import 'package:flutter_bloc/flutter_bloc.dart';
import '../../models/duplicate_match.dart';
import '../../models/face_match_result.dart';
import '../../utils/http/api_exception.dart';
import '../../services/staff_service.dart';
import './face_enrolment_state.dart';

/// Takes the photos + embeddings produced by [FaceCaptureCubit] (owned by the
/// `face` feature) and uploads them for a specific staff member. Kept
/// separate from [FaceCaptureCubit] so `face/` never has to know about
/// `StaffService` — the dependency only goes one way.
class FaceEnrolmentCubit extends Cubit<FaceEnrolmentSubmitState> {
  FaceEnrolmentCubit(this._service) : super(const FaceEnrolmentSubmitState());

  final StaffService _service;

  /// [reason] says why an already-enrolled person is being enrolled again.
  /// If the face already belongs to another staff member the backend refuses
  /// and the state becomes [FaceEnrolmentSubmitStatus.duplicateFound]; the
  /// admin can then submit again with [allowDuplicate] and a reason.
  Future<void> submit({
    required String staffId,
    required List<FaceSample> shots,
    String? reason,
    bool allowDuplicate = false,
  }) async {
    emit(const FaceEnrolmentSubmitState(status: FaceEnrolmentSubmitStatus.submitting));
    try {
      await _service.enroll(id: staffId, shots: shots, reason: reason, allowDuplicate: allowDuplicate);
      emit(const FaceEnrolmentSubmitState(status: FaceEnrolmentSubmitStatus.success));
    } on ApiException catch (e) {
      if (e.code == 'duplicate_face') {
        emit(
          FaceEnrolmentSubmitState(
            status: FaceEnrolmentSubmitStatus.duplicateFound,
            duplicates: DuplicateMatch.listFrom(e.details),
          ),
        );
      } else {
        emit(FaceEnrolmentSubmitState(status: FaceEnrolmentSubmitStatus.error, errorMessage: e.message));
      }
    }
  }

  /// Back to the review screen after a duplicate warning was dismissed.
  void dismissDuplicate() => emit(const FaceEnrolmentSubmitState());
}
