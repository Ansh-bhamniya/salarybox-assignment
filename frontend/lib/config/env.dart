import 'package:flutter/foundation.dart';

/// App-wide config that would normally vary per build flavor.
///
/// [apiBaseUrl] defaults to the deployed Vercel backend, so a plain
/// `flutter build apk --release` produces an APK that works on a real device.
/// Override at build time with `--dart-define=API_BASE_URL=...` — e.g.
/// `http://10.0.2.2:4000` to hit a backend running on the host machine from
/// the Android emulator.
class Env {
  Env._();

  static const apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'https://salarybox-backend.vercel.app',
  );

  /// Shows the liveness tuning screen (a link on the login screen) so the head-turn
  /// check can be measured on a real device. Off in normal builds:
  /// `--dart-define=LIVENESS_DEBUG=true`.
  static const livenessDebug = bool.fromEnvironment('LIVENESS_DEBUG');

  /// Whether the live camera stream arrives mirrored, the way a mirror shows it,
  /// which flips which way a head turn reads. **Measured on an iPhone: true**
  /// (turning to your own left moves the nose toward the frame's left).
  /// Android is assumed false and still needs checking with the liveness debug
  /// screen. Override with `--dart-define=LIVENESS_FRAMES_MIRRORED=true|false`.
  static bool get livenessFramesMirrored => switch (const String.fromEnvironment('LIVENESS_FRAMES_MIRRORED')) {
    'true' => true,
    'false' => false,
    _ => defaultTargetPlatform == TargetPlatform.iOS,
  };

  /// Identifies the bundled face model (`assets/models/mobilefacenet.tflite`) to
  /// the backend, which stores it with every enrolment so faces made by
  /// different models are never compared. Change it whenever the model file
  /// changes.
  static const faceModelVersion = 'mobilefacenet-192-v1';

  /// How many photos an enrolment takes (front, slightly left, slightly right).
  /// The person is matched against all of them, and the best score counts.
  static const enrolmentShots = 3;

  /// Sanity check between the photos of one enrolment: a later photo that
  /// scores below this against the first is probably a different person or a
  /// bad shot, and is retaken. Deliberately well under [faceMatchThreshold] so
  /// natural head turns and lighting changes still pass.
  static const enrolmentMinSimilarity = 0.4;

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
