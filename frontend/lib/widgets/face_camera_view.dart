import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/camera_capture_controller.dart';
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
  const FaceCameraView({
    super.key,
    required this.camera,
    required this.onCapture,
    this.busy = false,
  });

  final CameraCaptureController camera;
  final VoidCallback onCapture;
  final bool busy;

  @override
  State<FaceCameraView> createState() => _FaceCameraViewState();
}

class _FaceCameraViewState extends State<FaceCameraView>
    with WidgetsBindingObserver {
  late final FaceGuidanceAnalyzer _analyzer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Portrait only while the camera is up (the framing oval and face
    // detection assume it) — the rest of the app stays free to rotate.
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    _analyzer = FaceGuidanceAnalyzer(
      sensorOrientation:
          widget.camera.controller!.description.sensorOrientation,
    );
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
          _CoverPreview(controller: controller),
          ValueListenableBuilder<FaceGuidance>(
            valueListenable: _analyzer.guidance,
            builder: (context, guidance, _) {
              final good = guidance == FaceGuidance.good;
              return Stack(
                fit: StackFit.expand,
                children: [
                  CustomPaint(
                    painter: _OvalMaskPainter(
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
                        _ShutterButton(
                          enabled: !widget.busy,
                          onTap: widget.onCapture,
                        ),
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

/// Fills the whole screen with the preview, cropping the overflow instead of
/// letterboxing it (a raw [CameraPreview] keeps the sensor's aspect ratio and
/// leaves black bars).
class _CoverPreview extends StatelessWidget {
  const _CoverPreview({required this.controller});

  final CameraController controller;

  @override
  Widget build(BuildContext context) {
    final previewSize = controller.value.previewSize;
    if (previewSize == null) return const SizedBox.shrink();

    // previewSize is reported in sensor (landscape) terms; the UI is locked
    // to portrait, so the short side is the width.
    final width = previewSize.width < previewSize.height
        ? previewSize.width
        : previewSize.height;
    final height = previewSize.width < previewSize.height
        ? previewSize.height
        : previewSize.width;

    return ClipRect(
      child: FittedBox(
        fit: BoxFit.cover,
        child: SizedBox(
          width: width,
          height: height,
          child: CameraPreview(controller),
        ),
      ),
    );
  }
}

Rect _ovalRect(Size size) {
  final width = size.width * 0.72;
  final height = width * 1.3;
  return Rect.fromCenter(
    center: Offset(size.width / 2, size.height * 0.44),
    width: width,
    height: height,
  );
}

class _OvalMaskPainter extends CustomPainter {
  const _OvalMaskPainter({required this.ringColor});

  final Color ringColor;

  @override
  void paint(Canvas canvas, Size size) {
    final oval = _ovalRect(size);

    final scrim = Path()
      ..fillType = PathFillType.evenOdd
      ..addRect(Offset.zero & size)
      ..addOval(oval);
    canvas.drawPath(
      scrim,
      Paint()..color = Colors.black.withValues(alpha: 0.55),
    );

    canvas.drawOval(
      oval,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..color = ringColor,
    );
  }

  @override
  bool shouldRepaint(_OvalMaskPainter oldDelegate) =>
      oldDelegate.ringColor != ringColor;
}

class _GuidancePill extends StatelessWidget {
  const _GuidancePill({required this.guidance});

  final FaceGuidance guidance;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final good = guidance == FaceGuidance.good;
    // "Good" uses the accent, so its text must be the colour meant for it
    // (white on purple in light mode, black on white in dark mode).
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
          Text(guidance.message, style: TextStyle(color: foreground, fontWeight: FontWeight.w600)),
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
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
