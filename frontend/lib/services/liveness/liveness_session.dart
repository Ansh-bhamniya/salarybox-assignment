import 'dart:math';
import './face_observation.dart';

/// The numbers that decide what counts as a turn. Measured on a real iPhone
/// (about 28 analysed frames a second): looking straight the nose sits a little
/// off the middle of the eyes and that offset differs from person to person,
/// so a turn is judged **against the person's own straight-ahead baseline**,
/// taken while they hold still at the start. A real 12-25° turn moves the nose
/// about 0.25 eye-distances, 50° about 0.65.
class LivenessConfig {
  const LivenessConfig({
    this.turnYawDegrees = 14,
    this.turnRatio = 0.15,
    this.neutralYawDegrees = 8,
    this.neutralRatio = 0.10,
    this.startRatioMax = 0.15,
    this.turnHold = const Duration(milliseconds: 100),
    this.holdStillFor = const Duration(milliseconds: 700),
    this.finalHoldFor = const Duration(milliseconds: 500),
    this.holdGrace = const Duration(milliseconds: 150),
    this.turnTimeout = const Duration(seconds: 6),
    this.sessionTimeout = const Duration(seconds: 20),
    this.faceLostGrace = const Duration(milliseconds: 800),
    this.maxYawJumpDegrees = 45,
    this.maxTrustedYawDegrees = 55,
    this.trackReassignGrace = const Duration(milliseconds: 1200),
    this.trackReassignDistance = 0.25,
    this.disagreeFor = const Duration(milliseconds: 300),
    this.disagreeRatioFraction = 0.5,
    this.peakYawTarget = 20,
    this.peakYawMin = 12,
    this.peakYawMax = 28,
  });

  /// A turn needs the head at least this far round from straight (ML Kit's Euler Y size)...
  /// (14°: on a real phone a clear turn showed the nose well past its limit at 16°, so 18° rejected honest turns.)
  final double turnYawDegrees;

  /// ...and the nose at least this far further off the eye middle than when straight (eye-distances).
  final double turnRatio;

  /// "Looking straight", once the baseline is known: inside both of these.
  final double neutralYawDegrees;
  final double neutralRatio;

  /// To start, before any baseline exists: the head angle within [neutralYawDegrees]
  /// and the nose offset no bigger than this (a turned head is well past it).
  final double startRatioMax;

  /// How long a turn must be held, so one noisy frame can't pass it.
  final Duration turnHold;

  final Duration holdStillFor;
  final Duration finalHoldFor;

  /// A "still" pose may be broken this long (a noisy frame) before the hold starts over.
  final Duration holdGrace;

  final Duration turnTimeout;
  final Duration sessionTimeout;

  /// How long the face may vanish from the frame before that counts.
  final Duration faceLostGrace;

  /// Between two consecutive frames the head can't plausibly rotate more than this.
  final double maxYawJumpDegrees;

  /// Further round than this the nose reading stops being trustworthy (the eyes
  /// line up and it explodes or flips sign), so such frames say nothing about direction.
  final double maxTrustedYawDegrees;

  /// The tracker sometimes gives the same face a new id when it turns; that is
  /// accepted if the face reappears within this long and no further than
  /// [trackReassignDistance] (as a fraction of the frame) from where it was.
  /// Anything else counts as a different face.
  final Duration trackReassignGrace;
  final double trackReassignDistance;

  /// How long the head angle can say "turned" while the nose barely moved
  /// (below [disagreeRatioFraction] of [turnRatio]) before it is judged a flat
  /// picture being rotated.
  final Duration disagreeFor;
  final double disagreeRatioFraction;

  /// The frame kept for identity from each turn is the one whose head angle is
  /// closest to [peakYawTarget], within [peakYawMin]..[peakYawMax] (beyond
  /// that the face embedding stops being reliable).
  final double peakYawTarget;
  final double peakYawMin;
  final double peakYawMax;
}

enum LivenessPhase { waitingForFace, holdStill, turning, lookStraight, passed, failed }

enum LivenessFailure {
  /// A step took too long.
  timeout,

  /// Turned toward the other side than asked.
  wrongDirection,

  /// The face left the picture.
  faceLost,

  /// A second person came into view.
  multipleFaces,

  /// The tracked face was replaced by another one.
  faceChanged,

  /// The head angle jumped further than a head can move between frames.
  implausibleMotion,

  /// The head angle and the nose disagree: not a real, turning head.
  notLive,
}

/// Which camera frames the session wants kept, because it will match the
/// person's identity on them.
enum FrameRole {
  /// Looking straight, before the turns.
  start,

  /// The best frame of a turn (closest to the target angle so far).
  turnPeak,

  /// Looking straight, after the turns.
  finalStraight,
}

class KeepFrame {
  const KeepFrame(this.role, [this.turnIndex = 0]);

  final FrameRole role;

  /// Which turn, for [FrameRole.turnPeak].
  final int turnIndex;

  @override
  String toString() => 'KeepFrame($role, $turnIndex)';
}

/// What a passed session leaves behind, for the audit trail. Peaks are measured
/// from the person's own straight-ahead baseline.
class LivenessResult {
  const LivenessResult({
    required this.challenge,
    required this.duration,
    required this.peakYaws,
    required this.peakTurnRatios,
    required this.baselineYaw,
    required this.baselineRatio,
  });

  final List<TurnSide> challenge;
  final Duration duration;

  /// Per turn: how far round the head and nose were at the kept peak frame.
  final List<double> peakYaws;
  final List<double> peakTurnRatios;

  /// The straight-ahead readings the turns were measured from.
  final double baselineYaw;
  final double baselineRatio;
}

/// One "turn your head" check. Feed it a [FaceObservation] per analysed frame;
/// it moves waiting → hold still → the turns (in [challenge] order) → look
/// straight → passed, or fails for a specific [LivenessFailure].
///
/// Pure logic (no camera, no plugins), so every rule is unit-tested.
class LivenessSession {
  LivenessSession({required List<TurnSide> challenge, this.config = const LivenessConfig()})
    : challenge = List.unmodifiable(challenge),
      assert(challenge.isNotEmpty);

  /// A random challenge: turn one way, then the other, in random order.
  factory LivenessSession.random(Random random, {LivenessConfig config = const LivenessConfig()}) {
    final first = random.nextBool() ? TurnSide.left : TurnSide.right;
    return LivenessSession(challenge: [first, first.opposite], config: config);
  }

  final List<TurnSide> challenge;
  final LivenessConfig config;

  LivenessPhase _phase = LivenessPhase.waitingForFace;
  LivenessFailure? _failure;
  LivenessResult? _result;

  int _turnIndex = 0;
  Duration _phaseSince = Duration.zero;
  Duration? _sessionStart;
  Duration? _faceLostSince;
  Duration? _lastUsableAt;
  Duration? _neutralSince;
  Duration? _badSince;
  int? _trackingId;

  /// The person's own "looking straight" readings, fixed at the end of the hold.
  double _baselineYaw = 0;
  double _baselineRatio = 0;
  final List<double> _holdYaws = [];
  final List<double> _holdRatios = [];

  double? _lastYaw;
  ({double x, double y})? _lastCenter;
  Duration? _turnSince;
  Duration? _disagreeSince;

  /// Whether the person has left the side they were on, so being on the wrong
  /// side counts as a wrong turn rather than "still where they were".
  bool _armed = true;

  /// Whether head angle and nose offset move together or oppositely, fixed by
  /// the first turn; a change mid-session means the two disagree.
  int? _relationSign;

  final List<double> _peakYaws = [];
  final List<double> _peakRatios = [];
  double? _bestScore;
  double _bestYaw = 0;
  double _bestRatio = 0;

  LivenessPhase get phase => _phase;
  LivenessFailure? get failure => _failure;
  LivenessResult? get result => _result;
  bool get isFinished => _phase == LivenessPhase.passed || _phase == LivenessPhase.failed;
  int get turnsCompleted => _turnIndex;
  int get totalTurns => challenge.length;

  /// The person's straight-ahead readings, once the hold-still step has fixed them.
  double get baselineYaw => _baselineYaw;
  double get baselineRatio => _baselineRatio;

  /// The side to turn to right now, while a turn is being asked for.
  TurnSide? get target => _phase == LivenessPhase.turning ? challenge[_turnIndex] : null;

  /// Advances the check with one frame's observation. Returns which frame (if
  /// any) the caller should keep for identity matching.
  KeepFrame? onObservation(FaceObservation o) {
    if (isFinished) return null;
    final now = o.at;

    final started = _sessionStart;
    if (started != null && now - started > config.sessionTimeout) return _fail(LivenessFailure.timeout);

    // A step's own limit runs whether or not a face is visible right now.
    final askingForSomething = _phase == LivenessPhase.turning || _phase == LivenessPhase.lookStraight;
    if (askingForSomething && now - _phaseSince > config.turnTimeout) return _fail(LivenessFailure.timeout);

    if (o.faceCount > 1) {
      if (askingForSomething) return _fail(LivenessFailure.multipleFaces);
      _backToWaiting();
      return null;
    }

    if (!o.usable) {
      final since = _faceLostSince ??= _lastUsableAt ?? now;
      if (now - since > config.faceLostGrace) {
        if (askingForSomething) return _fail(LivenessFailure.faceLost);
        _backToWaiting();
      }
      return null;
    }
    final previousUsableAt = _lastUsableAt;
    _faceLostSince = null;
    _lastUsableAt = now;

    final yaw = o.yawDegrees!;
    final ratio = o.turnRatio!;

    // Same face throughout, once the check is under way. The tracker may re-id
    // a face that briefly dropped out while turning; that is fine if it comes
    // back in the same place straight away, not if it jumps or is gone a while.
    final id = o.trackingId;
    if (id != null) {
      if (_trackingId == null) {
        _trackingId = id;
      } else if (id != _trackingId) {
        if (!_isSameFaceAgain(o, previousUsableAt)) {
          if (askingForSomething) return _fail(LivenessFailure.faceChanged);
          _backToWaiting();
          _trackingId = id;
          return null;
        }
        _trackingId = id;
      }
    }
    if (o.centerX != null && o.centerY != null) _lastCenter = (x: o.centerX!, y: o.centerY!);

    final lastYaw = _lastYaw;
    _lastYaw = yaw;
    if (askingForSomething && lastYaw != null && (yaw - lastYaw).abs() > config.maxYawJumpDegrees) {
      return _fail(LivenessFailure.implausibleMotion);
    }

    switch (_phase) {
      case LivenessPhase.waitingForFace:
        if (_canStart(yaw, ratio, o.framing)) {
          _phase = LivenessPhase.holdStill;
          _phaseSince = now;
          _sessionStart = now;
          _badSince = null;
          _holdYaws
            ..clear()
            ..add(yaw);
          _holdRatios
            ..clear()
            ..add(ratio);
        }
        return null;

      case LivenessPhase.holdStill:
        if (!_canStart(yaw, ratio, o.framing)) {
          final since = _badSince ??= now;
          if (now - since > config.holdGrace) _backToWaiting();
          return null;
        }
        _badSince = null;
        _holdYaws.add(yaw);
        _holdRatios.add(ratio);
        if (now - _phaseSince >= config.holdStillFor) {
          _baselineYaw = _median(_holdYaws);
          _baselineRatio = _median(_holdRatios);
          _phase = LivenessPhase.turning;
          _phaseSince = now;
          _turnIndex = 0;
          _armed = true;
          return const KeepFrame(FrameRole.start);
        }
        return null;

      case LivenessPhase.turning:
        return _onTurning(o, yaw - _baselineYaw, ratio - _baselineRatio);

      case LivenessPhase.lookStraight:
        final relYaw = yaw - _baselineYaw;
        final relRatio = ratio - _baselineRatio;
        if (_isNeutral(relYaw, relRatio) && o.framing == FaceFraming.good) {
          _badSince = null;
          final since = _neutralSince ??= now;
          if (now - since >= config.finalHoldFor) {
            _phase = LivenessPhase.passed;
            _result = LivenessResult(
              challenge: challenge,
              duration: now - _sessionStart!,
              peakYaws: List.unmodifiable(_peakYaws),
              peakTurnRatios: List.unmodifiable(_peakRatios),
              baselineYaw: _baselineYaw,
              baselineRatio: _baselineRatio,
            );
            return const KeepFrame(FrameRole.finalStraight);
          }
        } else {
          // A noisy frame doesn't undo the hold; staying off-straight does.
          final since = _badSince ??= now;
          if (now - since > config.holdGrace) _neutralSince = null;
        }
        return null;

      case LivenessPhase.passed:
      case LivenessPhase.failed:
        return null;
    }
  }

  /// Call periodically even when no frames arrive (a stalled camera), so
  /// timeouts and a vanished face are still noticed.
  KeepFrame? onTick(Duration now) => onObservation(FaceObservation.noFace(at: now, frameIndex: -1));

  /// [relYaw] and [relRatio] are measured from the person's straight-ahead baseline.
  KeepFrame? _onTurning(FaceObservation o, double relYaw, double relRatio) {
    final now = o.at;
    // Far past a sensible turn the nose reading is unreliable: say nothing either way.
    if (relYaw.abs() > config.maxTrustedYawDegrees) return null;

    final want = challenge[_turnIndex];
    final side = relRatio > 0 ? TurnSide.left : TurnSide.right;
    final turned = relYaw.abs() >= config.turnYawDegrees && relRatio.abs() >= config.turnRatio;

    if (_isNeutral(relYaw, relRatio) || (turned && side == want)) _armed = true;

    // The angle says "turned" but the nose hasn't moved: a flat picture being rotated.
    if (relYaw.abs() >= config.turnYawDegrees && relRatio.abs() < config.turnRatio * config.disagreeRatioFraction) {
      final since = _disagreeSince ??= now;
      if (now - since >= config.disagreeFor) return _fail(LivenessFailure.notLive);
    } else {
      _disagreeSince = null;
    }

    if (!turned) {
      _turnSince = null;
      return null;
    }

    if (side != want) {
      _turnSince = null;
      return _armed ? _fail(LivenessFailure.wrongDirection) : null;
    }

    // Head angle and nose offset must keep moving the same way round.
    final relation = (relYaw > 0 ? 1 : -1) * (relRatio > 0 ? 1 : -1);
    final fixed = _relationSign ??= relation;
    if (relation != fixed) return _fail(LivenessFailure.notLive);

    KeepFrame? keep;
    final inWindow = relYaw.abs() >= config.peakYawMin && relYaw.abs() <= config.peakYawMax;
    final score = (relYaw.abs() - config.peakYawTarget).abs();
    if (inWindow && (_bestScore == null || score < _bestScore!)) {
      _bestScore = score;
      _bestYaw = relYaw;
      _bestRatio = relRatio;
      keep = KeepFrame(FrameRole.turnPeak, _turnIndex);
    }

    final since = _turnSince ??= now;
    if (now - since < config.turnHold) return keep;

    // Turn done. If no frame landed in the ideal window, keep this one.
    if (_bestScore == null) {
      _bestYaw = relYaw;
      _bestRatio = relRatio;
      keep = KeepFrame(FrameRole.turnPeak, _turnIndex);
    }
    _peakYaws.add(_bestYaw);
    _peakRatios.add(_bestRatio);
    _bestScore = null;
    _turnSince = null;
    _armed = false;
    _turnIndex++;
    _phaseSince = now;
    if (_turnIndex >= challenge.length) {
      _phase = LivenessPhase.lookStraight;
      _neutralSince = null;
      _badSince = null;
    }
    return keep;
  }

  bool _isSameFaceAgain(FaceObservation o, Duration? previousUsableAt) {
    final last = _lastCenter;
    if (last == null || previousUsableAt == null || o.centerX == null || o.centerY == null) return false;
    if (o.at - previousUsableAt > config.trackReassignGrace) return false;
    final dx = o.centerX! - last.x;
    final dy = o.centerY! - last.y;
    return sqrt(dx * dx + dy * dy) <= config.trackReassignDistance;
  }

  /// Ready to begin: head roughly straight, nose not far off centre, face well framed.
  bool _canStart(double yaw, double ratio, FaceFraming? framing) =>
      yaw.abs() <= config.neutralYawDegrees && ratio.abs() <= config.startRatioMax && framing == FaceFraming.good;

  bool _isNeutral(double relYaw, double relRatio) =>
      relYaw.abs() <= config.neutralYawDegrees && relRatio.abs() <= config.neutralRatio;

  static double _median(List<double> values) {
    final sorted = [...values]..sort();
    final middle = sorted.length ~/ 2;
    return sorted.length.isOdd ? sorted[middle] : (sorted[middle - 1] + sorted[middle]) / 2;
  }

  void _backToWaiting() {
    _phase = LivenessPhase.waitingForFace;
    _trackingId = null;
    _sessionStart = null;
    _lastYaw = null;
    _lastCenter = null;
    _faceLostSince = null;
    _lastUsableAt = null;
    _badSince = null;
    _holdYaws.clear();
    _holdRatios.clear();
  }

  KeepFrame? _fail(LivenessFailure reason) {
    _phase = LivenessPhase.failed;
    _failure = reason;
    return null;
  }
}
