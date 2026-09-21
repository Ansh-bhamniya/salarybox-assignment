import './face_observation.dart';

enum DirectionTestStage { straight, left, straightAgain, right, done }

/// What a finished [DirectionTest] found.
class DirectionTestResult {
  const DirectionTestResult({
    required this.baseline,
    required this.leftMove,
    required this.rightMove,
    required this.minMove,
  });

  /// The nose reading looking straight, and how far it moved for each turn (raw:
  /// positive = nose toward the frame's right, before any mirroring flag).
  final double baseline;
  final double leftMove;
  final double rightMove;
  final double minMove;

  /// Both turns moved the nose clearly, and in opposite directions.
  bool get conclusive => leftMove.abs() >= minMove && rightMove.abs() >= minMove && leftMove * rightMove < 0;

  /// Whether this device hands over mirrored frames: true if turning to the
  /// person's own left moved the nose toward the frame's *left*. Null if inconclusive.
  bool? get framesMirrored => conclusive ? leftMove < 0 : null;

  String get summary => conclusive
      ? 'Left turn moved the nose ${leftMove > 0 ? 'right' : 'left'} in the frame, right turn moved it '
            '${rightMove > 0 ? 'right' : 'left'} → frames are ${framesMirrored! ? '' : 'NOT '}mirrored.'
      : 'Inconclusive (left ${leftMove.toStringAsFixed(2)}, right ${rightMove.toStringAsFixed(2)}, '
            'need at least ±${minMove.toStringAsFixed(2)} in opposite directions). Turn further and try again.';
}

/// A guided check of which way is "left" on this device: look straight, turn to
/// **your own left**, look straight, turn to **your own right**. Compares how
/// the nose moved in each case, so the result doesn't depend on any library's
/// sign convention. Pure logic, driven by observations.
class DirectionTest {
  DirectionTest({
    this.minMove = 0.12,
    this.straightFor = const Duration(milliseconds: 1200),
    this.turnFor = const Duration(milliseconds: 2500),
    this.returnFor = const Duration(milliseconds: 1500),
  });

  final double minMove;
  final Duration straightFor;
  final Duration turnFor;
  final Duration returnFor;

  DirectionTestStage _stage = DirectionTestStage.straight;
  Duration? _stageStart;
  final List<double> _straight = [];
  double? _leftBest;
  double? _rightBest;
  DirectionTestResult? _result;

  DirectionTestStage get stage => _stage;
  DirectionTestResult? get result => _result;
  bool get isDone => _stage == DirectionTestStage.done;

  /// What to tell the person right now.
  String get prompt => switch (_stage) {
    DirectionTestStage.straight => 'Look straight at the camera',
    DirectionTestStage.left => 'Turn to YOUR LEFT and hold',
    DirectionTestStage.straightAgain => 'Look straight again',
    DirectionTestStage.right => 'Turn to YOUR RIGHT and hold',
    DirectionTestStage.done => _result?.conclusive == true ? 'Done' : 'Try again',
  };

  /// [rawRatio] is the nose reading with no mirroring applied (positive = nose toward the frame's right).
  void onObservation(FaceObservation o, {required double? rawRatio}) {
    if (isDone) return;
    final start = _stageStart ??= o.at;
    final elapsed = o.at - start;

    if (rawRatio != null && o.usable) {
      switch (_stage) {
        case DirectionTestStage.straight:
          _straight.add(rawRatio);
        case DirectionTestStage.left:
          _leftBest = _furthest(_leftBest, rawRatio);
        case DirectionTestStage.right:
          _rightBest = _furthest(_rightBest, rawRatio);
        case DirectionTestStage.straightAgain:
        case DirectionTestStage.done:
          break;
      }
    }

    final length = switch (_stage) {
      DirectionTestStage.straight => straightFor,
      DirectionTestStage.left || DirectionTestStage.right => turnFor,
      DirectionTestStage.straightAgain => returnFor,
      DirectionTestStage.done => Duration.zero,
    };
    if (elapsed < length) return;

    _stageStart = o.at;
    _stage = switch (_stage) {
      DirectionTestStage.straight => DirectionTestStage.left,
      DirectionTestStage.left => DirectionTestStage.straightAgain,
      DirectionTestStage.straightAgain => DirectionTestStage.right,
      DirectionTestStage.right => DirectionTestStage.done,
      DirectionTestStage.done => DirectionTestStage.done,
    };
    if (_stage == DirectionTestStage.done) _finish();
  }

  /// The reading furthest from the straight-ahead baseline, which is only known
  /// after the first stage; comparison happens in [_finish], so keep the extremes.
  double _furthest(double? best, double value) {
    if (best == null) return value;
    final baseline = _straight.isEmpty ? 0.0 : _median(_straight);
    return (value - baseline).abs() > (best - baseline).abs() ? value : best;
  }

  void _finish() {
    final baseline = _straight.isEmpty ? 0.0 : _median(_straight);
    _result = DirectionTestResult(
      baseline: baseline,
      leftMove: (_leftBest ?? baseline) - baseline,
      rightMove: (_rightBest ?? baseline) - baseline,
      minMove: minMove,
    );
  }

  static double _median(List<double> values) {
    final sorted = [...values]..sort();
    final middle = sorted.length ~/ 2;
    return sorted.length.isOdd ? sorted[middle] : (sorted[middle - 1] + sorted[middle]) / 2;
  }
}

/// Convenience for the debug screen: the raw nose reading from an observation
/// that was produced with [framesMirrored] applied.
double? rawRatioOf(FaceObservation o, {required bool framesMirrored}) {
  final ratio = o.turnRatio;
  if (ratio == null) return null;
  return framesMirrored ? -ratio : ratio;
}
