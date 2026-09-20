/// App-wide config that would normally vary per build flavor.
///
/// [apiBaseUrl] defaults to the Android emulator's alias for the host
/// machine's localhost (10.0.2.2). Override at build time with
/// `--dart-define=API_BASE_URL=https://your-host:4000` when running against
/// a physical device or a deployed backend.
class Env {
  Env._();

  static const apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://10.0.2.2:4000',
  );

  /// Cosine-similarity threshold above which two face embeddings (from the
  /// bundled MobileFaceNet model) are considered the same person.
  ///
  /// Measured offline on LFW (5 identities, 3,900 same-person and 16,000
  /// different-person pairs, same crop/resize/normalize as the app): different
  /// people scored -0.36..0.58 (95th pct 0.32), same person 0.21..0.81
  /// (5th..95th pct). 0.55 sits just above every impostor score seen. Real
  /// selfies taken inside the framing oval should score higher than LFW's
  /// press photos, so this is a conservative starting point — tune from real
  /// enrol/attempt pairs (in debug/profile builds every comparison logs
  /// `[face] similarity=…`).
  static const faceMatchThreshold = 0.55;

  /// Shows the raw match score on the attendance result screens. Off for
  /// normal builds; turn on while calibrating the threshold with
  /// `--dart-define=SHOW_MATCH_SCORE=true`.
  static const showMatchScore = bool.fromEnvironment('SHOW_MATCH_SCORE');
}
