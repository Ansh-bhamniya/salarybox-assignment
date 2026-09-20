import 'package:flutter_bloc/flutter_bloc.dart';
import '../../utils/http/api_exception.dart';
import '../../services/staff_service.dart';
import './face_enrolment_state.dart';

/// Takes the embedding + photo produced by [FaceCaptureCubit] (owned by the
/// `face` feature) and uploads them for a specific staff member. Kept
/// separate from [FaceCaptureCubit] so `face/` never has to know about
/// `StaffService` — the dependency only goes one way.
class FaceEnrolmentCubit extends Cubit<FaceEnrolmentSubmitState> {
  FaceEnrolmentCubit(this._service) : super(const FaceEnrolmentSubmitState());

  final StaffService _service;

  Future<void> submit({required String staffId, required String photoPath, required List<double> embedding}) async {
    emit(const FaceEnrolmentSubmitState(status: FaceEnrolmentSubmitStatus.submitting));
    try {
      await _service.enroll(id: staffId, photoPath: photoPath, embedding: embedding);
      emit(const FaceEnrolmentSubmitState(status: FaceEnrolmentSubmitStatus.success));
    } on ApiException catch (e) {
      emit(FaceEnrolmentSubmitState(status: FaceEnrolmentSubmitStatus.error, errorMessage: e.message));
    }
  }
}
