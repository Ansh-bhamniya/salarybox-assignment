/// What a guided camera screen shows the person right now. Enrolment and the
/// head-turn check both give the same kind of coaching — a step, a prompt, a
/// turn line over a target zone, a ring that fills while holding, a one-line
/// message — so they share one camera view, which only needs this.
abstract interface class CameraCoaching {
  /// The small heading above the prompt, e.g. "Photo 2 of 3" or "Turn 1 of 2".
  String get heading;

  /// Dots under the heading: [totalSteps] of them, the first [step] filled.
  int get step;
  int get totalSteps;

  /// What to do right now, e.g. "Turn your head to the left".
  String get prompt;

  /// One short sentence about what to fix (or "hold still").
  String get message;

  /// Everything is right: the message shows in the accent colour.
  bool get good;

  /// A step was just completed: the ring turns to the accent colour.
  bool get saved;

  /// The camera is about to fire, or a step is being confirmed: a light tap.
  bool get capturing;

  /// How far the head is turned, in degrees, positive toward the person's own
  /// left, or null with no usable face.
  double? get turnDegrees;

  /// The range of [turnDegrees] that is right for now, drawn as the green zone.
  double get targetMin;
  double get targetMax;

  /// The ring around the oval is split into [ringSegments] pieces, one per step
  /// (per photo, or per part of the head-turn check). The first [ringDone] are
  /// complete, and [ringProgress] fills the next one.
  int get ringSegments;
  int get ringDone;

  /// 0..1 of the hold that is done, drawn as the piece of the ring being filled.
  double get ringProgress;
}
