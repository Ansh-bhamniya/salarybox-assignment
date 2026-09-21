import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../config/env.dart';
import '../config/theme/app_icons.dart';
import '../config/theme/app_radius.dart';
import '../services/camera_capture_controller.dart';
import '../services/liveness/camera_coaching.dart';
import '../services/liveness/liveness_analyzer.dart';
import './cover_camera_preview.dart';
import './face_oval_mask.dart';
import './turn_meter.dart';

/// Full-screen selfie camera for the pose-guided screens (enrolment and the
/// head-turn check): edge-to-edge preview, the framing oval, and under it a line
/// showing how far to turn, which step this is, what to do and how it is going. There is no shutter: [onFrame]
/// gets every analysed frame and whoever listens decides what to do with it,
/// while [guidance] says what to show.
///
/// Expects [camera] to be initialized. While [busy] (a photo is being taken and
/// processed) the live analysis pauses.
class PoseCameraView extends StatefulWidget {
  const PoseCameraView({
    super.key,
    required this.camera,
    required this.guidance,
    required this.onFrame,
    this.busy = false,
  });

  final CameraCaptureController camera;
  final ValueListenable<CameraCoaching> guidance;
  final void Function(AnalyzedFrame frame) onFrame;
  final bool busy;

  @override
  State<PoseCameraView> createState() => _PoseCameraViewState();
}

class _PoseCameraViewState extends State<PoseCameraView> with WidgetsBindingObserver {
  late final LivenessAnalyzer _analyzer;
  StreamSubscription<AnalyzedFrame>? _subscription;
  bool _wasSaved = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Portrait only while the camera is up (the framing oval and face
    // detection assume it) — the rest of the app stays free to rotate.
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    _analyzer = LivenessAnalyzer(
      sensorOrientation: widget.camera.controller!.description.sensorOrientation,
      framesMirrored: Env.livenessFramesMirrored,
    );
    _subscription = _analyzer.frames.listen((frame) => widget.onFrame(frame));
    widget.guidance.addListener(_onGuidance);
    _startStream();
  }

  /// A small tap when a photo is about to be taken and when it has been kept, so
  /// the person feels it without having to look.
  void _onGuidance() {
    final g = widget.guidance.value;
    if (g.capturing) HapticFeedback.lightImpact();
    if (g.saved && !_wasSaved) HapticFeedback.mediumImpact();
    _wasSaved = g.saved;
  }

  @override
  void didUpdateWidget(PoseCameraView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.busy != oldWidget.busy) {
      widget.busy ? _stopStream() : _startStream();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      if (!widget.busy) _startStream();
    } else {
      _stopStream();
    }
  }

  void _startStream() => widget.camera.startImageStream(_analyzer.onFrame);

  void _stopStream() => widget.camera.stopImageStream();

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    SystemChrome.setPreferredOrientations(DeviceOrientation.values);
    _stopStream();
    widget.guidance.removeListener(_onGuidance);
    _subscription?.cancel();
    _analyzer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.camera.controller!;
    final accent = Theme.of(context).colorScheme.primaryFixedDim;

    return ColoredBox(
      color: Colors.black,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final oval = faceOvalRect(constraints.biggest);

          return ValueListenableBuilder<CameraCoaching>(
            valueListenable: widget.guidance,
            builder: (context, guidance, _) {
              return Stack(
                fit: StackFit.expand,
                children: [
                  CoverCameraPreview(controller: controller),
                  CustomPaint(
                    painter: FaceOvalMaskPainter(
                      ringColor: guidance.saved ? accent : Colors.white.withValues(alpha: 0.85),
                      progress: guidance.ringProgress,
                      progressColor: accent,
                      segments: guidance.ringSegments,
                      segmentsDone: guidance.ringDone,
                    ),
                  ),
                  // Under the oval: the turn line (as wide as the oval), what to do (the one highlighted
                  // line), then how it is going, a little further down.
                  Positioned(
                    left: 16,
                    right: 16,
                    top: oval.bottom + 18,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(
                          width: oval.width,
                          child: TurnMeter(
                            turnDegrees: guidance.turnDegrees,
                            targetMin: guidance.targetMin,
                            targetMax: guidance.targetMax,
                            inPosition: guidance.good,
                          ),
                        ),
                        const SizedBox(height: 18),
                        _Instruction(guidance: guidance),
                        const SizedBox(height: 22),
                        _MessagePill(guidance: guidance),
                      ],
                    ),
                  ),
                  // Which step this is, at the bottom of the screen.
                  SafeArea(
                    child: Align(
                      alignment: Alignment.bottomCenter,
                      child: Padding(
                        padding: const EdgeInsets.only(bottom: 16),
                        child: _ShotPrompt(guidance: guidance),
                      ),
                    ),
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }
}

/// "Photo 2 of 3" with one dot per photo, at the bottom of the screen.
class _ShotPrompt extends StatelessWidget {
  const _ShotPrompt({required this.guidance});

  final CameraCoaching guidance;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final step = guidance.step;
    final total = guidance.totalSteps;

    return Semantics(
      label: guidance.heading,
      child: ExcludeSemantics(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              guidance.heading,
              style: theme.textTheme.labelLarge?.copyWith(color: Colors.white, fontWeight: FontWeight.w800),
            ),
            const SizedBox(width: 10),
            for (var i = 1; i <= total; i++)
              Container(
                width: 8,
                height: 8,
                margin: const EdgeInsets.only(right: 4),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: i <= step ? Colors.white : Colors.white.withValues(alpha: 0.35),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// What to do for this step, e.g. "Turn your head to the left", under the oval. It is the only
/// highlighted text on the screen: on the accent colour, so it is what the eye goes to.
class _Instruction extends StatelessWidget {
  const _Instruction({required this.guidance});

  final CameraCoaching guidance;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Semantics(
      label: '${guidance.heading}. ${guidance.prompt}',
      child: ExcludeSemantics(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          decoration: BoxDecoration(color: scheme.primaryFixedDim, borderRadius: AppRadius.pillBorder),
          child: Text(
            guidance.prompt,
            textAlign: TextAlign.center,
            style: Theme.of(
              context,
            ).textTheme.titleLarge?.copyWith(color: scheme.onPrimaryFixed, fontWeight: FontWeight.w800),
          ),
        ),
      ),
    );
  }
}

/// The one short sentence that says what to change (or "hold still"): plain text over the camera,
/// so the highlighted instruction above it stays the one thing that stands out.
class _MessagePill extends StatelessWidget {
  const _MessagePill({required this.guidance});

  final CameraCoaching guidance;

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primaryFixedDim;
    const shadows = [Shadow(color: Colors.black87, blurRadius: 6)];

    return Semantics(
      liveRegion: true,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            guidance.good ? AppIcons.checkFilled : AppIcons.face,
            size: 18,
            color: guidance.good ? accent : Colors.white,
            shadows: shadows,
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              guidance.message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 16, shadows: shadows),
            ),
          ),
        ],
      ),
    );
  }
}
