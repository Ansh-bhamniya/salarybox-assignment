import 'package:equatable/equatable.dart';

enum FaceCaptureStatus { initial, cameraReady, processing, ready, error }

class FaceCaptureState extends Equatable {
  const FaceCaptureState({
    this.status = FaceCaptureStatus.initial,
    this.photoPath,
    this.embedding,
    this.errorMessage,
  });

  final FaceCaptureStatus status;
  final String? photoPath;
  final List<double>? embedding;
  final String? errorMessage;

  FaceCaptureState copyWith({
    FaceCaptureStatus? status,
    String? photoPath,
    List<double>? embedding,
    String? errorMessage,
  }) {
    return FaceCaptureState(
      status: status ?? this.status,
      photoPath: photoPath ?? this.photoPath,
      embedding: embedding ?? this.embedding,
      errorMessage: errorMessage,
    );
  }

  @override
  List<Object?> get props => [status, photoPath, embedding, errorMessage];
}
