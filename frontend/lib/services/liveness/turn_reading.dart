/// How far a head is turned, as one steady number for the turn line.
///
/// Positive degrees are toward the person's own left, from the head angle
/// itself: its sign flickers far less than the nose offset's does around
/// straight. Which way the angle runs against the person's left depends on the
/// device, so it is learned from the first clear turn (the nose offset gives
/// the side there) and until then a default is used — measured on an iPhone,
/// where turning left makes the angle more negative. Each reading is smoothed
/// so the line does not jitter.
class TurnReading {
  TurnReading({this.defaultRelation = -1, this.smoothing = 0.6, this.learnAtDegrees = 10, this.learnNoseMin = 0.15});

  /// The sign to use before anything is learned: -1 means left is a negative angle.
  final int defaultRelation;

  /// How much of each new reading goes into the value (0..1); less is steadier.
  final double smoothing;

  /// A turn counts as clear enough to learn from at this many degrees and this nose offset.
  final double learnAtDegrees;
  final double learnNoseMin;

  int? _learned;
  double? _smoothed;

  /// The smoothed value from the last [read], or null since [clearSmoothing].
  double? get current => _smoothed;

  /// [relYaw] and [relRatio] are the head angle and nose offset measured from
  /// the person's straight-ahead baseline.
  double read(double relYaw, double relRatio) {
    if (relYaw.abs() >= learnAtDegrees && relRatio.abs() >= learnNoseMin) {
      _learned = (relYaw > 0 ? 1 : -1) * (relRatio > 0 ? 1 : -1);
    }
    final value = (_learned ?? defaultRelation) * relYaw;
    final previous = _smoothed;
    return _smoothed = previous == null ? value : previous + smoothing * (value - previous);
  }

  /// Forget the smoothing (the face was lost) but keep what was learned.
  void clearSmoothing() => _smoothed = null;

  /// Forget everything.
  void reset() {
    _learned = null;
    _smoothed = null;
  }
}
