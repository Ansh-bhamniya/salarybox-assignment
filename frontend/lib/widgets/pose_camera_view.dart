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
/// head-turn check): edge-to-edge preview, the framing oval, what to do now, and
/// a line under the oval showing how far to turn. There is no shutter: [onFrame]
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
                  SafeArea(
                    child: Align(
                      alignment: Alignment.topCenter,
                      child: Padding(
                        padding: const EdgeInsets.only(top: kToolbarHeight + 8),
                        child: _ShotPrompt(guidance: guidance),
                      ),
                    ),
                  ),
                  // The turn line, just under the oval and as wide as it is.
                  Positioned(
                    left: oval.left,
                    width: oval.width,
                    top: oval.bottom + 18,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        TurnMeter(
                          turnDegrees: guidance.turnDegrees,
                          targetMin: guidance.targetMin,
                          targetMax: guidance.targetMax,
                          inPosition: guidance.good,
                        ),
                        const SizedBox(height: 14),
                        _MessagePill(guidance: guidance),
                      ],
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

/// "Photo 2 of 3" with one dot per photo, and what to do for this one.
class _ShotPrompt extends StatelessWidget {
  const _ShotPrompt({required this.guidance});

  final CameraCoaching guidance;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final step = guidance.step;
    final total = guidance.totalSteps;

    return Semantics(
      label: '${guidance.heading}. ${guidance.prompt}',
      child: ExcludeSemantics(
        child: Column(
          children: [
            Row(
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
            const SizedBox(height: 4),
            Text(
              guidance.prompt,
              style: theme.textTheme.titleMedium?.copyWith(color: Colors.white, fontWeight: FontWeight.w700),
            ),
          ],
        ),
      ),
    );
  }
}

/// The one short sentence that says what to change (or "hold still").
class _MessagePill extends StatelessWidget {
  const _MessagePill({required this.guidance});

  final CameraCoaching guidance;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final good = guidance.good;
    // "Good" uses the accent, so its text must be the colour meant for it
    // (white on green in light mode, black on white in dark mode).
    final foreground = good ? scheme.onPrimary : Colors.white;

    return Semantics(
      liveRegion: true,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: good ? scheme.primary.withValues(alpha: 0.92) : Colors.black.withValues(alpha: 0.6),
          borderRadius: AppRadius.pillBorder,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(good ? AppIcons.checkFilled : AppIcons.face, size: 18, color: foreground),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                guidance.message,
                style: TextStyle(color: foreground, fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
