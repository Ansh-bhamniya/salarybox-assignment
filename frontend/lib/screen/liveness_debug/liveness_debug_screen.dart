import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import '../../config/env.dart';
import '../../services/camera_capture_controller.dart';
import '../../services/liveness/direction_test.dart';
import '../../services/liveness/face_observation.dart';
import '../../services/liveness/liveness_analyzer.dart';
import '../../services/liveness/liveness_session.dart';
import '../../utils/routes.dart';
import '../../widgets/app_back_button.dart';
import '../../widgets/cover_camera_preview.dart';
import '../../widgets/face_oval_mask.dart';

/// Measurement screen for the head-turn check, only reachable in builds made
/// with `--dart-define=LIVENESS_DEBUG=true`. Shows what the analyzer reads live
/// (head angle, nose offset, frame rate), what the check is waiting for, lets
/// you run the real challenge and a guided left/right direction test, and prints
/// the same numbers to the log so a session can be reviewed afterwards.
class LivenessDebugScreen extends StatefulWidget {
  const LivenessDebugScreen({super.key});

  @override
  State<LivenessDebugScreen> createState() => _LivenessDebugScreenState();
}

class _LivenessDebugScreenState extends State<LivenessDebugScreen> {
  static const _config = LivenessConfig();

  final _camera = CameraCaptureController();
  LivenessAnalyzer? _analyzer;
  StreamSubscription<FaceObservation>? _subscription;
  String? _error;

  bool _mirrored = Env.livenessFramesMirrored;
  FaceDetectorMode _mode = FaceDetectorMode.accurate;

  FaceObservation? _last;
  double _yawMin = 0, _yawMax = 0, _ratioMin = 0, _ratioMax = 0;
  LivenessSession? _session;
  DirectionTest? _directionTest;
  String? _directionSummary;
  LivenessPhase? _loggedPhase;
  int _lastLogMs = 0;

  @override
  void initState() {
    super.initState();
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    _start();
  }

  Future<void> _start() async {
    try {
      await _camera.initialize();
      final analyzer = LivenessAnalyzer(
        sensorOrientation: _camera.controller!.description.sensorOrientation,
        framesMirrored: _mirrored,
        mode: _mode,
      );
      _analyzer = analyzer;
      _subscription = analyzer.observations.listen(_onObservation);
      await _camera.startImageStream(analyzer.onFrame);
      if (mounted) setState(() {});
    } catch (e) {
      if (mounted) setState(() => _error = 'Could not open the camera: $e');
    }
  }

  void _onObservation(FaceObservation o) {
    if (!mounted) return;

    if (o.usable) {
      _yawMin = min(_yawMin, o.yawDegrees!);
      _yawMax = max(_yawMax, o.yawDegrees!);
      _ratioMin = min(_ratioMin, o.turnRatio!);
      _ratioMax = max(_ratioMax, o.turnRatio!);
    }

    final directionTest = _directionTest;
    if (directionTest != null && !directionTest.isDone) {
      directionTest.onObservation(o, rawRatio: rawRatioOf(o, framesMirrored: _mirrored));
      if (directionTest.isDone) _finishDirectionTest(directionTest.result!);
    }

    final session = _session;
    KeepFrame? keep;
    if (session != null && !session.isFinished) {
      keep = session.onObservation(o);
      if (session.phase != _loggedPhase) {
        _loggedPhase = session.phase;
        debugPrint(
          '[liveness] PHASE ${session.phase.name} target=${session.target?.name} '
          'turns=${session.turnsCompleted}/${session.totalTurns} failure=${session.failure?.name} '
          'baseline=(yaw ${session.baselineYaw.toStringAsFixed(1)}, nose ${session.baselineRatio.toStringAsFixed(3)})',
        );
      }
    }
    if (keep != null) debugPrint('[liveness] KEEP ${keep.role.name} turn=${keep.turnIndex} frame=${o.frameIndex}');

    final nowMs = o.at.inMilliseconds;
    if (nowMs - _lastLogMs >= 250) {
      _lastLogMs = nowMs;
      final stats = _analyzer?.stats.value;
      debugPrint(
        '[liveness] t=$nowMs fps=${stats?.fps.toStringAsFixed(1)} lat=${stats?.latencyMs}ms '
        'buf=${stats?.frameWidth}x${stats?.frameHeight} mode=${_mode.name} mirrored=$_mirrored faces=${o.faceCount} id=${o.trackingId} '
        'yaw=${o.yawDegrees?.toStringAsFixed(1)} ratio=${o.turnRatio?.toStringAsFixed(3)} '
        'side=${o.side?.name} framing=${o.framing?.name} '
        'box=(x ${o.centerX?.toStringAsFixed(2)}, y ${o.centerY?.toStringAsFixed(2)}, w ${o.widthRatio?.toStringAsFixed(2)})',
      );
    }

    setState(() => _last = o);
  }

  void _finishDirectionTest(DirectionTestResult result) {
    _directionSummary = result.summary;
    debugPrint(
      '[liveness] DIRTEST baseline=${result.baseline.toStringAsFixed(3)} '
      'leftMove=${result.leftMove.toStringAsFixed(3)} rightMove=${result.rightMove.toStringAsFixed(3)} '
      'conclusive=${result.conclusive} framesMirrored=${result.framesMirrored}',
    );
    final mirrored = result.framesMirrored;
    if (mirrored != null) {
      _mirrored = mirrored;
      _analyzer?.setFramesMirrored(mirrored);
    }
  }

  void _resetPeaks() => setState(() {
    _yawMin = _yawMax = _ratioMin = _ratioMax = 0;
    debugPrint('[liveness] --- peaks reset ---');
  });

  void _startCheck() {
    setState(() {
      _directionTest = null;
      _session = LivenessSession.random(Random());
    });
    debugPrint('[liveness] START check challenge=${_session!.challenge.map((s) => s.name).join(',')}');
  }

  void _startDirectionTest() {
    setState(() {
      _session = null;
      _directionSummary = null;
      _directionTest = DirectionTest();
    });
    debugPrint('[liveness] START direction test');
  }

  void _toggleMirrored() {
    setState(() => _mirrored = !_mirrored);
    _analyzer?.setFramesMirrored(_mirrored);
    debugPrint('[liveness] mirrored=$_mirrored');
  }

  Future<void> _toggleMode() async {
    final next = _mode == FaceDetectorMode.accurate ? FaceDetectorMode.fast : FaceDetectorMode.accurate;
    await _analyzer?.setMode(next);
    setState(() => _mode = next);
    debugPrint('[liveness] mode=${next.name}');
  }

  void _leave() {
    if (context.canPop()) {
      context.pop();
    } else {
      context.go(Routes.splash);
    }
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _camera.stopImageStream();
    _analyzer?.dispose();
    _camera.dispose();
    SystemChrome.setPreferredOrientations(DeviceOrientation.values);
    super.dispose();
  }

  // ---- what to show ---------------------------------------------------------

  /// The person's own straight-ahead readings once a check has fixed them, else zero.
  ({double yaw, double ratio}) get _baseline {
    final session = _session;
    final fixed =
        session != null &&
        (session.phase == LivenessPhase.turning ||
            session.phase == LivenessPhase.lookStraight ||
            session.phase == LivenessPhase.passed);
    return fixed ? (yaw: session.baselineYaw, ratio: session.baselineRatio) : (yaw: 0.0, ratio: 0.0);
  }

  /// A plain-words reading of the current pose against the same limits the check uses.
  String _poseLabel(FaceObservation? o) {
    if (o == null || !o.usable) return 'NO FACE';
    final base = _baseline;
    final relYaw = o.yawDegrees! - base.yaw;
    final relRatio = o.turnRatio! - base.ratio;
    final turned = relYaw.abs() >= _config.turnYawDegrees && relRatio.abs() >= _config.turnRatio;
    if (turned) return relRatio > 0 ? 'TURNED LEFT' : 'TURNED RIGHT';
    if (relYaw.abs() <= _config.neutralYawDegrees && relRatio.abs() <= _config.neutralRatio) return 'STRAIGHT';
    return 'turning…';
  }

  /// What the check is waiting for, so "why isn't it starting" has an answer.
  List<Widget> _startChecklist(FaceObservation? o) {
    if (o == null || !o.usable) {
      return [const _CheckLine(ok: false, text: 'a single face in view')];
    }
    final yawOk = o.yawDegrees!.abs() <= _config.neutralYawDegrees;
    final noseOk = o.turnRatio!.abs() <= _config.startRatioMax;
    final framed = o.framing == FaceFraming.good;
    return [
      _CheckLine(
        ok: yawOk,
        text: 'head straight   yaw ${o.yawDegrees!.toStringAsFixed(1)}° (within ${_config.neutralYawDegrees.round()})',
      ),
      _CheckLine(
        ok: noseOk,
        text: 'not turned   nose ${o.turnRatio!.toStringAsFixed(2)} (within ${_config.startRatioMax})',
      ),
      _CheckLine(ok: framed, text: 'face in the oval   ${_framingText(o)}'),
    ];
  }

  String _framingText(FaceObservation o) {
    final x = o.centerX!, y = o.centerY!, w = o.widthRatio!;
    final numbers = 'x ${x.toStringAsFixed(2)} y ${y.toStringAsFixed(2)} w ${w.toStringAsFixed(2)}';
    return switch (o.framing!) {
      FaceFraming.good => 'ok ($numbers)',
      FaceFraming.tooFar => 'move closer ($numbers)',
      FaceFraming.tooClose => 'move back ($numbers)',
      FaceFraming.offCenter =>
        '${y < 0.27
            ? 'too high'
            : y > 0.63
            ? 'too low'
            : 'off to the side'} ($numbers)',
    };
  }

  String? get _prompt {
    final test = _directionTest;
    if (test != null && !test.isDone) return _withArrow(test.prompt);

    final session = _session;
    if (session == null) return null;
    return switch (session.phase) {
      LivenessPhase.waitingForFace => 'Look at the camera, in the oval',
      LivenessPhase.holdStill => 'Hold still…',
      LivenessPhase.turning => _withArrow('Turn to your ${session.target!.name.toUpperCase()}'),
      LivenessPhase.lookStraight => 'Look straight',
      LivenessPhase.passed => 'PASSED',
      LivenessPhase.failed => 'FAILED: ${session.failure!.name}',
    };
  }

  /// The preview is mirrored like a mirror, so the person's own left is the screen's left.
  String _withArrow(String text) {
    if (text.contains('LEFT')) return '←  $text';
    if (text.contains('RIGHT')) return '$text  →';
    return text;
  }

  // ---- layout ---------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final controller = _camera.controller;

    return Scaffold(
      backgroundColor: Colors.black,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        // This screen is the app's front door in a debug build, so "back" leads into the normal app.
        leading: AppBackButton(onDark: true, onPressed: _leave),
        leadingWidth: AppBackButton.leadingWidth,
        title: const Text('Liveness debug'),
        actions: [
          TextButton(
            onPressed: _leave,
            child: const Text('Open app', style: TextStyle(color: Colors.white)),
          ),
          const SizedBox(width: 8),
        ],
        titleTextStyle: Theme.of(
          context,
        ).textTheme.titleLarge?.copyWith(color: Colors.white, fontWeight: FontWeight.w800),
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 0,
        systemOverlayStyle: SystemUiOverlayStyle.light,
      ),
      body: _error != null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(_error!, style: const TextStyle(color: Colors.white)),
              ),
            )
          : controller == null || !controller.value.isInitialized
          ? const Center(child: CircularProgressIndicator(color: Colors.white))
          : Stack(
              fit: StackFit.expand,
              children: [
                CoverCameraPreview(controller: controller),
                CustomPaint(
                  painter: FaceOvalMaskPainter(
                    ringColor: _last?.framing == FaceFraming.good
                        ? Theme.of(context).colorScheme.primaryFixedDim
                        : Colors.white.withValues(alpha: 0.85),
                  ),
                ),
                SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(8, kToolbarHeight + 4, 8, 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _Card(child: _topInfo()),
                        const Spacer(),
                        _Card(child: _readings()),
                        const SizedBox(height: 8),
                        _controls(),
                      ],
                    ),
                  ),
                ),
                if (_prompt != null)
                  IgnorePointer(
                    child: Align(alignment: const Alignment(0, -0.12), child: _Prompt(_prompt!)),
                  ),
              ],
            ),
    );
  }

  Widget _topInfo() {
    final o = _last;
    final stats = _analyzer?.stats.value;
    final session = _session;
    final waitingToStart =
        session == null || session.phase == LivenessPhase.waitingForFace || session.phase == LivenessPhase.holdStill;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '${stats?.fps.toStringAsFixed(0) ?? '-'} fps · ${stats?.latencyMs ?? '-'} ms · ${_mode.name} · '
          'mirrored: $_mirrored · buf ${stats?.frameWidth}x${stats?.frameHeight}',
          style: _mono,
        ),
        const SizedBox(height: 4),
        if (waitingToStart) ..._startChecklist(o),
        if (session != null && session.phase == LivenessPhase.passed) ...[
          Text(
            'PASSED in ${(session.result!.duration.inMilliseconds / 1000).toStringAsFixed(1)} s · '
            'baseline yaw ${session.result!.baselineYaw.toStringAsFixed(1)}° nose ${session.result!.baselineRatio.toStringAsFixed(2)}',
            style: _mono,
          ),
          Text(
            'peaks yaw ${session.result!.peakYaws.map((v) => v.toStringAsFixed(1)).join(', ')} · '
            'nose ${session.result!.peakTurnRatios.map((v) => v.toStringAsFixed(2)).join(', ')}',
            style: _mono,
          ),
        ],
        if (session != null && session.phase == LivenessPhase.failed)
          Text('FAILED: ${session.failure!.name}', style: _mono.copyWith(color: Colors.redAccent)),
        if (_directionSummary != null) ...[
          const SizedBox(height: 4),
          Text(_directionSummary!, style: _mono.copyWith(color: Colors.lightGreenAccent)),
        ],
      ],
    );
  }

  Widget _readings() {
    final o = _last;
    final base = _baseline;
    final relYaw = (o?.yawDegrees ?? 0) - base.yaw;
    final relRatio = (o?.turnRatio ?? 0) - base.ratio;
    final hasBaseline = base.yaw != 0 || base.ratio != 0;
    final usable = o != null && o.usable;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Center(
          child: Text(
            _poseLabel(o),
            style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w800, letterSpacing: 1),
          ),
        ),
        const SizedBox(height: 6),
        _Meter(
          title: 'head angle${hasBaseline ? ' vs baseline' : ''}',
          value: usable ? relYaw : null,
          threshold: _config.turnYawDegrees,
          range: 45,
          format: (v) => '${v.toStringAsFixed(1)}°',
        ),
        const SizedBox(height: 6),
        _Meter(
          title: 'nose offset${hasBaseline ? ' vs baseline' : ''}',
          // Negated so the person's left (positive) is drawn on the left, like the head-angle line.
          value: usable ? -relRatio : null,
          threshold: _config.turnRatio,
          range: 0.7,
          format: (v) => (-v).toStringAsFixed(2),
        ),
        const SizedBox(height: 4),
        Text(
          '← your left   (marks = what counts as a turn)   your right →',
          textAlign: TextAlign.center,
          style: _mono.copyWith(fontSize: 10, color: Colors.white60),
        ),
        Text(
          'peaks since reset:  yaw ${_yawMin.toStringAsFixed(0)}..${_yawMax.toStringAsFixed(0)}   '
          'nose ${_ratioMin.toStringAsFixed(2)}..${_ratioMax.toStringAsFixed(2)}',
          textAlign: TextAlign.center,
          style: _mono.copyWith(fontSize: 10, color: Colors.white60),
        ),
      ],
    );
  }

  Widget _controls() {
    final running = _session != null && !_session!.isFinished;
    return Wrap(
      spacing: 8,
      runSpacing: 6,
      alignment: WrapAlignment.center,
      children: [
        FilledButton(onPressed: _startCheck, child: Text(running ? 'Restart check' : 'Start check')),
        FilledButton.tonal(onPressed: _startDirectionTest, child: const Text('Direction test')),
        OutlinedButton(onPressed: _resetPeaks, style: _outlined, child: const Text('Reset peaks')),
        OutlinedButton(
          onPressed: _toggleMirrored,
          style: _outlined,
          child: Text('Mirrored: ${_mirrored ? 'on' : 'off'}'),
        ),
        OutlinedButton(onPressed: _toggleMode, style: _outlined, child: Text('Mode: ${_mode.name}')),
      ],
    );
  }

  static final _outlined = OutlinedButton.styleFrom(
    foregroundColor: Colors.white,
    backgroundColor: Colors.black54,
    side: const BorderSide(color: Colors.white54),
  );

  static const _mono = TextStyle(color: Colors.white, fontFamily: 'Menlo', fontSize: 11, height: 1.35);
}

class _Card extends StatelessWidget {
  const _Card({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.62), borderRadius: BorderRadius.circular(10)),
      child: Padding(padding: const EdgeInsets.all(10), child: child),
    );
  }
}

class _CheckLine extends StatelessWidget {
  const _CheckLine({required this.ok, required this.text});

  final bool ok;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      '${ok ? '✓' : '✗'} $text',
      style: TextStyle(
        color: ok ? Colors.lightGreenAccent : Colors.orangeAccent,
        fontFamily: 'Menlo',
        fontSize: 11,
        height: 1.35,
      ),
    );
  }
}

class _Prompt extends StatelessWidget {
  const _Prompt(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.55), borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w800),
        ),
      ),
    );
  }
}

/// A centre-zero bar: the dot shows the reading, the marks show what counts as a turn.
class _Meter extends StatelessWidget {
  const _Meter({
    required this.title,
    required this.value,
    required this.threshold,
    required this.range,
    required this.format,
  });

  final String title;
  final double? value;
  final double threshold;
  final double range;
  final String Function(double) format;

  @override
  Widget build(BuildContext context) {
    final v = value;
    final turned = v != null && v.abs() >= threshold;

    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              title,
              style: const TextStyle(color: Colors.white70, fontFamily: 'Menlo', fontSize: 10),
            ),
            Text(
              v == null ? '—' : format(v),
              style: TextStyle(
                color: turned ? Colors.lightGreenAccent : Colors.white,
                fontFamily: 'Menlo',
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
        const SizedBox(height: 3),
        SizedBox(
          height: 16,
          child: CustomPaint(
            size: const Size(double.infinity, 16),
            painter: _MeterPainter(value: v, threshold: threshold, range: range),
          ),
        ),
      ],
    );
  }
}

class _MeterPainter extends CustomPainter {
  const _MeterPainter({required this.value, required this.threshold, required this.range});

  final double? value;
  final double threshold;
  final double range;

  @override
  void paint(Canvas canvas, Size size) {
    final mid = size.width / 2;
    double xOf(double v) => mid + (v.clamp(-range, range) / range) * mid;

    canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromLTWH(0, size.height / 2 - 3, size.width, 6), const Radius.circular(3)),
      Paint()..color = Colors.white24,
    );

    final mark = Paint()
      ..color = Colors.white70
      ..strokeWidth = 2;
    for (final x in [xOf(-threshold), xOf(threshold)]) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), mark);
    }
    canvas.drawLine(Offset(mid, 3), Offset(mid, size.height - 3), Paint()..color = Colors.white38);

    final v = value;
    if (v == null) return;
    final x = xOf(v);
    final turned = v.abs() >= threshold;
    final color = turned ? Colors.lightGreenAccent : Colors.white;
    canvas.drawLine(
      Offset(mid, size.height / 2),
      Offset(x, size.height / 2),
      Paint()
        ..color = color.withValues(alpha: 0.6)
        ..strokeWidth = 6,
    );
    canvas.drawCircle(Offset(x, size.height / 2), 7, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_MeterPainter old) => old.value != value || old.threshold != threshold || old.range != range;
}
