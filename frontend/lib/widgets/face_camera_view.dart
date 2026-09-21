import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/camera_capture_controller.dart';
import './cover_camera_preview.dart';
import './face_oval_mask.dart';
import '../services/face_guidance.dart';
import '../config/theme/app_radius.dart';
import '../config/theme/app_icons.dart';

/// Full-screen selfie camera: edge-to-edge preview, an oval framing guide
/// that turns green when the face is well placed, live coaching text and a
/// shutter button. Shared by face enrolment and mark attendance.
///
/// Expects [camera] to be initialized. While [busy] (a capture is being
/// processed) the live analysis pauses and the shutter is disabled.
class FaceCameraView extends StatefulWidget {
  const FaceCameraView({super.key, required this.camera, required this.onCapture, this.busy = false});

  final CameraCaptureController camera;
  final VoidCallback onCapture;
  final bool busy;

  @override
  State<FaceCameraView> createState() => _FaceCameraViewState();
}

class _FaceCameraViewState extends State<FaceCameraView> with WidgetsBindingObserver {
  late final FaceGuidanceAnalyzer _analyzer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Portrait only while the camera is up (the framing oval and face
    // detection assume it) — the rest of the app stays free to rotate.
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    _analyzer = FaceGuidanceAnalyzer(sensorOrientation: widget.camera.controller!.description.sensorOrientation);
    _startStream();
  }

  @override
  void didUpdateWidget(FaceCameraView oldWidget) {
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
    _analyzer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.camera.controller!;

    return ColoredBox(
      color: Colors.black,
      child: Stack(
        fit: StackFit.expand,
        children: [
          CoverCameraPreview(controller: controller),
          ValueListenableBuilder<FaceGuidance>(
            valueListenable: _analyzer.guidance,
            builder: (context, guidance, _) {
              final good = guidance == FaceGuidance.good;
              return Stack(
                fit: StackFit.expand,
                children: [
                  CustomPaint(
                    painter: FaceOvalMaskPainter(
                      ringColor: good
                          ? Theme.of(context).colorScheme.primaryFixedDim
                          : Colors.white.withValues(alpha: 0.85),
                    ),
                  ),
                  SafeArea(
                    child: Column(
                      children: [
                        const SizedBox(height: kToolbarHeight + 8),
                        _GuidancePill(guidance: guidance),
                        const Spacer(),
                        _ShutterButton(enabled: !widget.busy, onTap: widget.onCapture),
                        const SizedBox(height: 32),
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _GuidancePill extends StatelessWidget {
  const _GuidancePill({required this.guidance});

  final FaceGuidance guidance;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final good = guidance == FaceGuidance.good;
    // "Good" uses the accent, so its text must be the colour meant for it
    // (white on green in light mode, black on white in dark mode).
    final foreground = good ? scheme.onPrimary : Colors.white;

    return AnimatedContainer(
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
          Text(
            guidance.message,
            style: TextStyle(color: foreground, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}

class _ShutterButton extends StatelessWidget {
  const _ShutterButton({required this.enabled, required this.onTap});

  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Capture photo',
      child: GestureDetector(
        onTap: enabled ? onTap : null,
        child: AnimatedOpacity(
          duration: const Duration(milliseconds: 150),
          opacity: enabled ? 1 : 0.4,
          child: Container(
            width: 78,
            height: 78,
            padding: const EdgeInsets.all(5),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 4),
            ),
            child: const DecoratedBox(
              decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.white),
            ),
          ),
        ),
      ),
    );
  }
}
