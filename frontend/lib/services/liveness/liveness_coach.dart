import './camera_coaching.dart';
import './face_observation.dart';
import './liveness_session.dart';
import './turn_reading.dart';

/// What the head-turn check shows the person at one moment.
class LivenessGuidance implements CameraCoaching {
  const LivenessGuidance({
    required this.phase,
    required this.heading,
    required this.step,
    required this.totalSteps,
    required this.prompt,
    required this.message,
    required this.good,
    required this.targetMin,
    required this.targetMax,
    this.saved = false,
    this.capturing = false,
    this.turnDegrees,
    this.ringProgress = 0,
  });

  final LivenessPhase phase;

  @override
  final String heading;
  @override
  final int step;
  @override
  final int totalSteps;
  @override
  final String prompt;
  @override
  final String message;
  @override
  final bool good;
  @override
  final bool saved;
  @override
  final bool capturing;
  @override
  final double? turnDegrees;
  @override
  final double targetMin;
  @override
  final double targetMax;
  @override
  final double ringProgress;
}

/// Turns a [LivenessSession] and the latest frame into [LivenessGuidance]: the
/// prompt, the turn line over its target zone, the ring, and one sentence about
/// what to fix. Call [coach] after handing the same observation to the session.
class LivenessCoach {
  LivenessCoach(this.session, {TurnReading? turn}) : _turn = turn ?? TurnReading();

  final LivenessSession session;
  final TurnReading _turn;
  int _lastTurnsCompleted = 0;

  /// Whether the person has left the side of the previous turn, so being on the
  /// wrong side now is a mistake rather than where they still are from before.
  bool _armed = true;

  LivenessConfig get _config => session.config;

  /// The guidance before any frame has been seen.
  LivenessGuidance idle() => _waiting(null);

  LivenessGuidance coach(FaceObservation o) {
    final done = session.turnsCompleted;
    final turnJustDone = done > _lastTurnsCompleted;
    if (turnJustDone) _armed = false;
    _lastTurnsCompleted = done;

    if (!o.usable) _turn.clearSmoothing();
    final turn = o.usable
        ? _turn.read(o.yawDegrees! - session.baselineYaw, o.turnRatio! - session.baselineRatio)
        : null;

    switch (session.phase) {
      case LivenessPhase.waitingForFace:
        return _waiting(o, turn: turn);
      case LivenessPhase.holdStill:
        return _straight(
          heading: 'Get ready',
          step: 0,
          prompt: 'Hold still…',
          message: 'Perfect — hold still',
          good: true,
          turn: turn,
        );
      case LivenessPhase.turning:
        return _turning(o, turn, turnJustDone: turnJustDone);
      case LivenessPhase.lookStraight:
        final neutral = o.usable && _isStraight(o);
        return _straight(
          heading: 'Almost done',
          step: session.totalTurns,
          prompt: 'Now look straight at the camera',
          message: neutral ? 'Perfect — hold still' : 'Look straight at the camera',
          good: neutral,
          turn: turn,
          capturing: turnJustDone,
        );
      case LivenessPhase.passed:
        return _straight(
          heading: 'Done',
          step: session.totalTurns,
          prompt: 'Checking it is you…',
          message: 'Verifying…',
          good: true,
          saved: true,
          turn: turn,
        );
      case LivenessPhase.failed:
        return _straight(
          heading: 'Try again',
          step: 0,
          prompt: 'That did not work',
          message: messageForFailure(session.failure!),
          good: false,
          turn: turn,
        );
    }
  }

  LivenessGuidance _waiting(FaceObservation? o, {double? turn}) {
    final String message;
    if (o == null || o.faceCount == 0) {
      message = 'Position your face inside the oval';
    } else if (o.faceCount > 1) {
      message = 'Only one person should be in frame';
    } else if (!o.usable) {
      message = 'Position your face inside the oval';
    } else {
      message = switch (o.framing) {
        FaceFraming.tooFar => 'Move a little closer',
        FaceFraming.tooClose => 'Move back a little',
        FaceFraming.offCenter => 'Center your face in the oval',
        _ => _isStraight(o) || _looksStartable(o) ? 'Perfect — hold still' : 'Look straight at the camera',
      };
    }
    return _straight(
      heading: 'Get ready',
      step: 0,
      prompt: 'Look at the camera, inside the oval',
      message: message,
      good: false,
      turn: turn,
    );
  }

  LivenessGuidance _turning(FaceObservation o, double? turn, {required bool turnJustDone}) {
    final side = session.target!;
    final left = side == TurnSide.left;
    final zone = (min: _config.turnYawDegrees, max: _config.peakYawMax);
    final index = session.turnsCompleted;

    // Signed like the turn line: positive is the person's left.
    final inZone = turn != null && (left ? turn >= zone.min : turn <= -zone.min);
    // Back near straight (on the raw reading: the smoothed line lags), or already going the right way.
    final nearStraight = o.usable && (o.yawDegrees! - session.baselineYaw).abs() < 6;
    if (nearStraight || inZone) _armed = true;
    final wrongWay = _armed && turn != null && (left ? turn <= -6 : turn >= 6);
    final String message;
    if (turn == null) {
      message = 'Keep your face inside the oval';
    } else if (wrongWay) {
      message = left ? 'Turn the other way, to your left' : 'Turn the other way, to your right';
    } else if (inZone) {
      message = 'Good — keep going';
    } else if (index > 0) {
      message = 'Now turn to the other side';
    } else {
      message = 'Turn a little more';
    }

    return LivenessGuidance(
      phase: LivenessPhase.turning,
      heading: 'Turn ${index + 1} of ${session.totalTurns}',
      step: index + 1,
      totalSteps: session.totalTurns,
      prompt: 'Turn your head to the ${left ? 'left' : 'right'}',
      message: message,
      good: inZone,
      capturing: turnJustDone,
      turnDegrees: turn,
      targetMin: left ? zone.min : -zone.max,
      targetMax: left ? zone.max : -zone.min,
    );
  }

  LivenessGuidance _straight({
    required String heading,
    required int step,
    required String prompt,
    required String message,
    required bool good,
    double? turn,
    bool saved = false,
    bool capturing = false,
  }) {
    return LivenessGuidance(
      phase: session.phase,
      heading: heading,
      step: step,
      totalSteps: session.totalTurns,
      prompt: prompt,
      message: message,
      good: good,
      saved: saved,
      capturing: capturing,
      turnDegrees: turn,
      targetMin: -_config.neutralYawDegrees,
      targetMax: _config.neutralYawDegrees,
      ringProgress: session.holdProgress,
    );
  }

  /// Straight against the person's own baseline (known once the hold has finished).
  bool _isStraight(FaceObservation o) {
    final relYaw = o.yawDegrees! - session.baselineYaw;
    final relRatio = o.turnRatio! - session.baselineRatio;
    return relYaw.abs() <= _config.neutralYawDegrees && relRatio.abs() <= _config.neutralRatio;
  }

  /// Before a baseline exists: roughly straight, judged on the raw readings.
  bool _looksStartable(FaceObservation o) =>
      o.yawDegrees!.abs() <= _config.neutralYawDegrees && o.turnRatio!.abs() <= _config.startRatioMax;

  /// What to tell the person when the check failed.
  static String messageForFailure(LivenessFailure failure) => switch (failure) {
    LivenessFailure.timeout => 'That took too long. Turn your head as asked.',
    LivenessFailure.wrongDirection => "You turned the wrong way. Watch which side you're asked for.",
    LivenessFailure.faceLost => 'We lost sight of your face. Keep it inside the oval.',
    LivenessFailure.multipleFaces => 'Only the person marking attendance should be in view.',
    LivenessFailure.faceChanged => 'The face in view changed. Only you should be in the picture.',
    LivenessFailure.implausibleMotion => 'The picture moved too suddenly. Hold the phone steady.',
    LivenessFailure.notLive => "The check didn't see a natural head turn. Turn slowly.",
  };
}
