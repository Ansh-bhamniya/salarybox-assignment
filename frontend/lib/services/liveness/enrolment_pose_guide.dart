import 'dart:math';
import './camera_coaching.dart';
import './face_observation.dart';
import './turn_reading.dart';

/// The poses an enrolment asks for, in order: straight on, then a little to
/// each side, so the templates cover a small change of angle later.
enum EnrolmentPose {
  straight('Look straight at the camera'),
  left('Turn your head to the left'),
  right('Turn your head to the right');

  const EnrolmentPose(this.prompt);

  /// What to tell the person for this photo.
  final String prompt;
}

/// What the guide is currently telling the person.
enum PoseAdvice {
  noFace,
  multipleFaces,
  moveCloser,
  moveBack,
  centerFace,
  lookStraight,
  turnMore,
  turnBack,
  wrongWay,
  holdStill,

  /// A photo was just taken and kept: a short pause before the next pose.
  saved,
}

/// The limits for each pose. Measured on a real iPhone: a clear 12-25° turn
/// moves the nose about 0.25 eye-distances; looking straight the nose sits a
/// little off centre, differently for each person.
class EnrolmentPoseConfig {
  const EnrolmentPoseConfig({
    this.straightYawDegrees = 8,
    this.straightRatioMax = 0.15,
    this.straightRelRatioMax = 0.10,
    this.turnMinDegrees = 14,
    this.turnMaxDegrees = 26,
    this.turnNoseMin = 0.15,
    this.wrongWayDegrees = 6,
    this.maxTrustedYawDegrees = 55,
    this.holdStraightFor = const Duration(milliseconds: 1500),
    this.holdTurnFor = const Duration(milliseconds: 1500),
    this.holdGrace = const Duration(milliseconds: 150),
    this.savedFor = const Duration(milliseconds: 1000),
    this.steadyDegrees = 3,
    this.steadyCenter = 0.05,
    this.defaultYawRelation = -1,
    this.smoothing = 0.6,
    this.stillStraightMaxYaw = 12,
    this.stillTurnMinYaw = 10,
    this.stillTurnMaxYaw = 34,
    this.stillCenterTolerance = 0.25,
    this.stillMinWidth = 0.22,
    this.stillMaxWidth = 0.80,
  });

  /// Straight on: the head within this many degrees, and (before a personal
  /// baseline exists) the nose no further than [straightRatioMax] off centre.
  final double straightYawDegrees;
  final double straightRatioMax;

  /// Once the baseline is known: how far the nose may drift from it.
  final double straightRelRatioMax;

  /// A turn photo is taken with the head this far round from straight, and the
  /// nose at least [turnNoseMin] further off centre than when straight (which
  /// is what tells a real turn from a rotated flat picture).
  final double turnMinDegrees;
  final double turnMaxDegrees;
  final double turnNoseMin;

  /// Turned this far the wrong way counts as "wrong way" rather than "not turned yet".
  final double wrongWayDegrees;

  /// Beyond this the nose reading is unreliable (see `LivenessConfig`).
  final double maxTrustedYawDegrees;

  /// How long the pose must be held before the photo is taken.
  final Duration holdStraightFor;
  final Duration holdTurnFor;

  /// A wobble or a noisy frame this short doesn't restart the hold.
  final Duration holdGrace;

  /// How long the "photo saved" pause lasts before the next pose is asked for.
  final Duration savedFor;

  /// The head angle may not vary more than this while holding...
  final double steadyDegrees;

  /// ...nor the face box move more than this (as a fraction of the frame).
  final double steadyCenter;

  /// Which way the ML Kit head angle runs against the person's own left: -1 means
  /// turning to your left makes the angle more negative (measured on an iPhone
  /// with mirrored frames). It is learned from the first clear turn on any device.
  final int defaultYawRelation;

  /// How much of each new reading goes into the turn line (0..1); less is steadier.
  final double smoothing;

  /// The photo that was actually taken is checked again (the person may have
  /// moved between the trigger and the shutter). Straight: within this yaw.
  /// Turned: between these two (looser than the trigger window).
  final double stillStraightMaxYaw;
  final double stillTurnMinYaw;
  final double stillTurnMaxYaw;

  /// ...and the face on it must sit inside the oval, at a sensible size.
  final double stillCenterTolerance;
  final double stillMinWidth;
  final double stillMaxWidth;
}

/// What to show and whether to fire the camera.
class PoseGuidance implements CameraCoaching {
  const PoseGuidance({
    required this.advice,
    required this.message,
    required this.pose,
    required this.shotIndex,
    required this.totalShots,
    required this.targetMin,
    required this.targetMax,
    this.turnDegrees,
    this.photosDone = 0,
    this.holdProgress = 0,
    this.shouldCapture = false,
  });

  final PoseAdvice advice;

  /// One short sentence for the person, e.g. "Turn a little more".
  @override
  final String message;

  final EnrolmentPose pose;

  /// Which photo this is (0-based) out of [totalShots].
  final int shotIndex;
  final int totalShots;

  /// How far the head is turned right now, in degrees, **positive toward the
  /// person's own left**, measured from their straight-ahead baseline. Null if
  /// there is no usable face.
  @override
  final double? turnDegrees;

  /// The range of [turnDegrees] that is right for this photo.
  @override
  final double targetMin;
  @override
  final double targetMax;

  /// How many photos have been taken and kept so far.
  final int photosDone;

  /// 0..1: how much of the hold is done.
  final double holdProgress;

  /// True once, when the pose has been held long enough: take the photo now.
  final bool shouldCapture;

  /// In position and being held (or about to be taken).
  bool get inPosition => advice == PoseAdvice.holdStill;

  @override
  String get prompt => pose.prompt;

  @override
  String get heading => 'Photo ${shotIndex + 1} of $totalShots';

  @override
  int get step => shotIndex + 1;

  @override
  int get totalSteps => totalShots;

  @override
  bool get good => inPosition || advice == PoseAdvice.saved;

  @override
  bool get saved => advice == PoseAdvice.saved;

  @override
  bool get capturing => shouldCapture;

  /// One piece of the ring per photo (per direction): finished photos stay filled.
  @override
  int get ringSegments => totalShots;

  @override
  int get ringDone => photosDone;

  @override
  double get ringProgress => inPosition ? holdProgress : 0;
}

/// Watches the live pose and decides when each enrolment photo should be taken:
/// when the face is well placed in the oval and held at the pose asked for,
/// steadily, for a moment. Pure logic, so it is unit-tested.
///
/// Flow per photo: feed observations with [onObservation] until a guidance has
/// `shouldCapture`; take the photo; then call [shotAccepted] or [shotRejected].
class EnrolmentPoseGuide {
  EnrolmentPoseGuide({
    this.plan = const [EnrolmentPose.straight, EnrolmentPose.left, EnrolmentPose.right],
    this.config = const EnrolmentPoseConfig(),
  }) : assert(plan.isNotEmpty);

  final List<EnrolmentPose> plan;
  final EnrolmentPoseConfig config;

  int _index = 0;

  /// The person's own straight-ahead readings, fixed by the first accepted straight photo.
  double _baselineYaw = 0;
  double _baselineRatio = 0;
  bool _hasBaseline = false;

  Duration? _holdSince;
  Duration? _badSince;
  double _holdYawMin = 0;
  double _holdYawMax = 0;
  final List<double> _holdYaws = [];
  final List<double> _holdRatios = [];
  bool _captureRequested = false;
  ({double yaw, double ratio})? _pendingBaseline;

  // The face box during the hold, so a head that is drifting sideways isn't "still".
  double _cxMin = 0, _cxMax = 0, _cyMin = 0, _cyMax = 0;

  bool _justAccepted = false;
  Duration? _savedUntil;
  late final TurnReading _turn = TurnReading(
    defaultRelation: config.defaultYawRelation,
    smoothing: config.smoothing,
    learnNoseMin: config.turnNoseMin,
  );

  int get shotIndex => _index;
  int get totalShots => plan.length;
  bool get isComplete => _index >= plan.length;
  EnrolmentPose get pose => plan[min(_index, plan.length - 1)];

  double get baselineYaw => _baselineYaw;
  double get baselineRatio => _baselineRatio;

  /// The signed range of turn degrees (positive = the person's left) that is right for [pose].
  ({double min, double max}) get target => switch (pose) {
    EnrolmentPose.straight => (min: -config.straightYawDegrees, max: config.straightYawDegrees),
    EnrolmentPose.left => (min: config.turnMinDegrees, max: config.turnMaxDegrees),
    EnrolmentPose.right => (min: -config.turnMaxDegrees, max: -config.turnMinDegrees),
  };

  /// Whether the photo actually taken shows the pose asked for. [yawDegrees] is
  /// ML Kit's head angle on the taken photo; only its size is used (the photo
  /// isn't necessarily mirrored like the live stream). Null means unknown: accept.
  bool isStillAcceptable(double? yawDegrees) {
    if (yawDegrees == null) return true;
    final size = yawDegrees.abs();
    return switch (pose) {
      EnrolmentPose.straight => size <= config.stillStraightMaxYaw,
      EnrolmentPose.left || EnrolmentPose.right => size >= config.stillTurnMinYaw && size <= config.stillTurnMaxYaw,
    };
  }

  /// Why the photo that was actually taken can't be used, or null if it can.
  /// [centerX]/[centerY]/[widthRatio] describe the face on the photo, as fractions of it.
  String? stillProblem({double? yawDegrees, double? centerX, double? centerY, double? widthRatio}) {
    if (!isStillAcceptable(yawDegrees)) {
      return 'That one moved a little. Hold the pose and it will retake by itself.';
    }
    if (centerX != null && centerY != null && widthRatio != null) {
      final off =
          (centerX - 0.5).abs() > config.stillCenterTolerance ||
          (centerY - 0.45).abs() > config.stillCenterTolerance ||
          widthRatio < config.stillMinWidth ||
          widthRatio > config.stillMaxWidth;
      if (off) return 'Keep your face inside the oval. It will retake by itself.';
    }
    return null;
  }

  /// The largest head angle the photo may show before it is refused outright, for the current pose.
  double get maxStillYaw => pose == EnrolmentPose.straight ? 25 : config.stillTurnMaxYaw + 6;

  /// The guidance to show before any frame has been seen for the current pose.
  PoseGuidance idle() => _guidance(PoseAdvice.noFace, 'Position your face inside the oval');

  PoseGuidance onObservation(FaceObservation o) {
    if (isComplete || _captureRequested) {
      return _guidance(PoseAdvice.holdStill, 'Perfect — hold still', turn: _turnOf(o), progress: 1);
    }

    // A photo was just kept: give the person a moment before the next pose.
    if (_justAccepted) {
      _justAccepted = false;
      _savedUntil = o.at + config.savedFor;
    }
    final savedUntil = _savedUntil;
    if (savedUntil != null) {
      if (o.at < savedUntil) return _guidance(PoseAdvice.saved, 'Photo saved', turn: _turnOf(o));
      _savedUntil = null;
    }

    if (o.faceCount > 1) {
      _resetHold();
      return _guidance(PoseAdvice.multipleFaces, 'Only one person should be in frame');
    }
    if (!o.usable) {
      _bad(o.at);
      _turn.clearSmoothing();
      return _guidance(PoseAdvice.noFace, 'Position your face inside the oval');
    }

    final yaw = o.yawDegrees!;
    final ratio = o.turnRatio!;
    final relYaw = yaw - _baselineYaw;
    final relRatio = ratio - _baselineRatio;
    final turn = _turn.read(relYaw, relRatio);

    final framing = _framingAdvice(o);
    if (framing != null) {
      _bad(o.at);
      return _guidance(framing.$1, framing.$2, turn: turn);
    }

    final PoseAdvice? off;
    switch (pose) {
      case EnrolmentPose.straight:
        final ratioOk = _hasBaseline
            ? relRatio.abs() <= config.straightRelRatioMax
            : ratio.abs() <= config.straightRatioMax;
        off = (relYaw.abs() <= config.straightYawDegrees && ratioOk) ? null : PoseAdvice.lookStraight;
      case EnrolmentPose.left:
      case EnrolmentPose.right:
        off = _turnAdvice(relYaw.abs(), relRatio, want: pose == EnrolmentPose.left ? 1.0 : -1.0);
    }
    if (off != null) {
      _bad(o.at);
      return _guidance(off, _messageFor(off), turn: turn);
    }

    // In position: hold it steady.
    _badSince = null;
    _holdSince ??= o.at;
    if (_holdYaws.isEmpty) _holdYawMin = _holdYawMax = yaw;
    _holdYawMin = min(_holdYawMin, yaw);
    _holdYawMax = max(_holdYawMax, yaw);
    _holdYaws.add(yaw);
    _holdRatios.add(ratio);

    final cx = o.centerX ?? 0.5, cy = o.centerY ?? 0.45;
    if (_holdYaws.length == 1) {
      _cxMin = _cxMax = cx;
      _cyMin = _cyMax = cy;
    }
    _cxMin = min(_cxMin, cx);
    _cxMax = max(_cxMax, cx);
    _cyMin = min(_cyMin, cy);
    _cyMax = max(_cyMax, cy);

    final moving =
        _holdYawMax - _holdYawMin > config.steadyDegrees ||
        _cxMax - _cxMin > config.steadyCenter ||
        _cyMax - _cyMin > config.steadyCenter;
    if (moving) {
      // Still moving: start the hold again from this frame.
      _resetHold();
      _holdSince = o.at;
      _holdYawMin = _holdYawMax = yaw;
      _cxMin = _cxMax = cx;
      _cyMin = _cyMax = cy;
      _holdYaws.add(yaw);
      _holdRatios.add(ratio);
    }

    final holdFor = pose == EnrolmentPose.straight ? config.holdStraightFor : config.holdTurnFor;
    final elapsed = o.at - _holdSince!;
    final progress = (elapsed.inMicroseconds / holdFor.inMicroseconds).clamp(0.0, 1.0);

    if (elapsed >= holdFor) {
      _captureRequested = true;
      if (pose == EnrolmentPose.straight) {
        _pendingBaseline = (yaw: _median(_holdYaws), ratio: _median(_holdRatios));
      }
      return _guidance(PoseAdvice.holdStill, 'Perfect — hold still', turn: turn, progress: 1, capture: true);
    }
    return _guidance(PoseAdvice.holdStill, 'Perfect — hold still', turn: turn, progress: progress);
  }

  /// The photo was taken and passed every check: on to the next pose.
  void shotAccepted() {
    final pending = _pendingBaseline;
    if (pending != null && !_hasBaseline && pose == EnrolmentPose.straight) {
      _baselineYaw = pending.yaw;
      _baselineRatio = pending.ratio;
      _hasBaseline = true;
    }
    _pendingBaseline = null;
    _index++;
    _resetHold();
    _justAccepted = true;
  }

  /// The photo was taken but didn't pass (or failed): ask for the same pose again.
  void shotRejected() {
    _pendingBaseline = null;
    _resetHold();
  }

  /// Start over from the first pose.
  void reset() {
    _index = 0;
    _baselineYaw = 0;
    _baselineRatio = 0;
    _hasBaseline = false;
    _pendingBaseline = null;
    _turn.reset();
    _savedUntil = null;
    _justAccepted = false;
    _resetHold();
  }

  // ---- internals ------------------------------------------------------------

  /// A frame that isn't right: the hold survives a moment of it, not longer.
  void _bad(Duration now) {
    final since = _badSince ??= now;
    if (now - since > config.holdGrace) _resetHold();
  }

  void _resetHold() {
    _holdSince = null;
    _badSince = null;
    _captureRequested = false;
    _holdYaws.clear();
    _holdRatios.clear();
  }

  /// Where the face sits in the oval. A turned head shifts and narrows its
  /// box, so turned photos allow a little more room than straight ones.
  (PoseAdvice, String)? _framingAdvice(FaceObservation o) {
    final x = o.centerX, y = o.centerY, w = o.widthRatio;
    if (x == null || y == null || w == null) return null;

    final turned = pose != EnrolmentPose.straight;
    final xTolerance = turned ? 0.22 : 0.15;
    final yTolerance = turned ? 0.22 : 0.18;
    final minWidth = turned ? 0.25 : 0.30;
    final maxWidth = turned ? 0.78 : 0.70;

    if (w < minWidth) return (PoseAdvice.moveCloser, 'Move a little closer');
    if (w > maxWidth) return (PoseAdvice.moveBack, 'Move back a little');
    if ((x - 0.5).abs() > xTolerance || (y - 0.45).abs() > yTolerance) {
      return (PoseAdvice.centerFace, 'Center your face in the oval');
    }
    return null;
  }

  /// [want] is +1 for the person's left, -1 for their right.
  PoseAdvice? _turnAdvice(double relYawSize, double relRatio, {required double want}) {
    if (relYawSize > config.maxTrustedYawDegrees) return PoseAdvice.turnBack;
    final side = relRatio > 0 ? 1.0 : -1.0;

    if (side != want && relYawSize >= config.wrongWayDegrees) return PoseAdvice.wrongWay;
    if (relYawSize < config.turnMinDegrees || relRatio.abs() < config.turnNoseMin || side != want) {
      return PoseAdvice.turnMore;
    }
    if (relYawSize > config.turnMaxDegrees) return PoseAdvice.turnBack;
    return null;
  }

  String _messageFor(PoseAdvice advice) => switch (advice) {
    PoseAdvice.lookStraight => 'Look straight at the camera',
    PoseAdvice.turnMore => 'Turn a little more',
    PoseAdvice.turnBack => 'Not that far — turn back a little',
    PoseAdvice.wrongWay =>
      pose == EnrolmentPose.left ? 'Turn the other way, to your left' : 'Turn the other way, to your right',
    _ => '',
  };

  double? _turnOf(FaceObservation o) => o.usable ? _turn.current : null;

  PoseGuidance _guidance(PoseAdvice advice, String message, {double? turn, double progress = 0, bool capture = false}) {
    final range = target;
    return PoseGuidance(
      advice: advice,
      message: message,
      pose: pose,
      shotIndex: min(_index, plan.length - 1),
      totalShots: plan.length,
      turnDegrees: turn,
      targetMin: range.min,
      targetMax: range.max,
      photosDone: min(_index, plan.length),
      holdProgress: progress,
      shouldCapture: capture,
    );
  }

  static double _median(List<double> values) {
    final sorted = [...values]..sort();
    final middle = sorted.length ~/ 2;
    return sorted.length.isOdd ? sorted[middle] : (sorted[middle - 1] + sorted[middle]) / 2;
  }
}
