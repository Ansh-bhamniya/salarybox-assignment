import 'package:equatable/equatable.dart';
import '../../models/face_match_result.dart';

enum FaceCaptureStatus { initial, cameraReady, processing, ready, error }

class FaceCaptureState extends Equatable {
  const FaceCaptureState({this.status = FaceCaptureStatus.initial, this.shots = const [], this.errorMessage});

  final FaceCaptureStatus status;

  /// The photos captured so far this enrolment, in order (frontal first).
  final List<FaceSample> shots;
  final String? errorMessage;

  FaceCaptureState copyWith({FaceCaptureStatus? status, List<FaceSample>? shots, String? errorMessage}) {
    return FaceCaptureState(status: status ?? this.status, shots: shots ?? this.shots, errorMessage: errorMessage);
  }

  @override
  List<Object?> get props => [status, shots.map((s) => s.imagePath).toList(), errorMessage];
}
