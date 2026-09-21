import 'dart:async';
import 'dart:ui' show Rect;
import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import '../camera_input_image.dart';
import './camera_frame.dart';
import './face_observation.dart';
import './pose_estimator.dart';

/// How fast the analysis is keeping up.
class AnalyzerStats {
  const AnalyzerStats({this.fps = 0, this.latencyMs = 0, this.frameWidth = 0, this.frameHeight = 0});

  /// Frames analysed per second, over the last couple of seconds.
  final double fps;

  /// How long the last frame took to analyse.
  final int latencyMs;

  /// The camera buffer's size as delivered (before any rotation).
  final int frameWidth;
  final int frameHeight;
}

/// One analysed frame: what it says ([observation]), a way to copy the picture
/// ([snapshot]) and where ML Kit found the face on it.
class AnalyzedFrame {
  const AnalyzedFrame({required this.observation, required this.snapshot, this.faceBox});

  final FaceObservation observation;

  /// Copies this frame's picture so it can be kept; null if its format can't be
  /// read. The camera reuses its buffers, so call it while handling the frame.
  final CameraFrame? Function() snapshot;

  /// The face's box in the upright picture, when exactly one face was found.
  final Rect? faceBox;
}

/// Runs face detection on the live camera stream and publishes one
/// [FaceObservation] per analysed frame.
///
/// Uses ML Kit's *accurate* mode with landmarks and tracking: the head angle is
/// only guaranteed in that mode (the live guidance runs the faster, coarser
/// one). Frames that arrive while a frame is still being analysed are dropped,
/// so the rate settles at whatever the phone can sustain.
class LivenessAnalyzer {
  LivenessAnalyzer({
    required this.sensorOrientation,
    bool framesMirrored = false,
    FaceDetectorMode mode = FaceDetectorMode.accurate,
  }) : _estimator = PoseEstimator(framesMirrored: framesMirrored),
       _mode = mode,
       _detector = _buildDetector(mode);

  final int sensorOrientation;

  PoseEstimator _estimator;
  FaceDetectorMode _mode;
  FaceDetector _detector;

  final Stopwatch _clock = Stopwatch()..start();
  final StreamController<AnalyzedFrame> _frames = StreamController.broadcast();
  final ValueNotifier<AnalyzerStats> stats = ValueNotifier(const AnalyzerStats());
  final List<int> _completedAtMs = [];

  bool _busy = false;
  bool _closed = false;
  int _frameIndex = 0;

  /// Every analysed frame with its picture, for whoever needs to keep some.
  Stream<AnalyzedFrame> get frames => _frames.stream;

  Stream<FaceObservation> get observations => _frames.stream.map((frame) => frame.observation);
  FaceDetectorMode get mode => _mode;
  bool get framesMirrored => _estimator.framesMirrored;

  static FaceDetector _buildDetector(FaceDetectorMode mode) => FaceDetector(
    options: FaceDetectorOptions(performanceMode: mode, enableLandmarks: true, enableTracking: true, minFaceSize: 0.15),
  );

  /// Tuning aid: flip the direction if the device delivers mirrored frames.
  void setFramesMirrored(bool mirrored) => _estimator = PoseEstimator(framesMirrored: mirrored);

  /// Tuning aid: compare the speed and steadiness of the two detector modes.
  Future<void> setMode(FaceDetectorMode mode) async {
    if (mode == _mode) return;
    final old = _detector;
    _mode = mode;
    _detector = _buildDetector(mode);
    await old.close();
  }

  Future<void> onFrame(CameraImage image) async {
    if (_busy || _closed) return;
    _busy = true;
    final startedMs = _clock.elapsedMilliseconds;

    try {
      final input = inputImageFromCameraImage(image, sensorOrientation);
      if (input == null) return;

      final faces = await _detector.processImage(input);
      if (_closed) return;

      final observation = _estimator.observe(
        faces: faces,
        frameSize: uprightFrameSize(image, sensorOrientation),
        at: _clock.elapsed,
        frameIndex: _frameIndex++,
      );
      _recordCompletion(startedMs, image);
      _frames.add(
        AnalyzedFrame(
          observation: observation,
          snapshot: () => CameraFrame.fromCameraImage(image, sensorOrientation),
          faceBox: faces.length == 1 ? faces.single.boundingBox : null,
        ),
      );
    } catch (_) {
      // One bad frame is not worth surfacing.
    } finally {
      _busy = false;
    }
  }

  void _recordCompletion(int startedMs, CameraImage image) {
    final now = _clock.elapsedMilliseconds;
    _completedAtMs.add(now);
    _completedAtMs.removeWhere((t) => now - t > 2000);
    stats.value = AnalyzerStats(
      fps: _completedAtMs.length / 2,
      latencyMs: now - startedMs,
      frameWidth: image.width,
      frameHeight: image.height,
    );
  }

  Future<void> dispose() async {
    _closed = true;
    await _frames.close();
    stats.dispose();
    await _detector.close();
  }
}
