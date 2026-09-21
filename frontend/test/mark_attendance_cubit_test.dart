import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' show Rect;
import 'package:dio/dio.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/bloc/mark_attendance/mark_attendance_cubit.dart';
import 'package:frontend/bloc/mark_attendance/mark_attendance_state.dart';
import 'package:frontend/models/face_match_result.dart';
import 'package:frontend/services/attendance_service.dart';
import 'package:frontend/services/camera_capture_controller.dart';
import 'package:frontend/services/face_embedding_service.dart';
import 'package:frontend/services/liveness/camera_frame.dart';
import 'package:frontend/services/liveness/face_observation.dart';
import 'package:frontend/services/liveness/liveness_analyzer.dart';
import 'package:frontend/services/liveness/liveness_session.dart';
import 'package:frontend/services/staff_service.dart';
import 'package:frontend/utils/http/api_client.dart';
import 'helpers/fake_http_adapter.dart';

/// A unit vector whose cosine with axis 0 is [cos] (living in the first two dimensions).
List<double> _atCos(double cos) => List<double>.filled(8, 0)
  ..[0] = cos
  ..[1] = sqrt(1 - cos * cos);
List<double> _axis(int i) => List<double>.filled(8, 0)..[i] = 1;

class _FakeCamera implements CameraCaptureController {
  var initialized = 0;
  var disposed = false;
  var failToOpen = false;

  @override
  Future<void> initialize() async {
    if (failToOpen) throw StateError('no camera');
    initialized++;
  }

  @override
  Future<void> dispose() async => disposed = true;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Hands out canned embeddings for the frames, in the order they are asked for.
class _FakeEmbeddings implements FaceEmbeddingService {
  _FakeEmbeddings(this.results);

  final List<List<double>> results;
  final calls = <({bool mirrored, String? savedTo})>[];
  final _real = FaceEmbeddingService();

  @override
  Future<FaceSample> embedFrame(
    CameraFrame frame,
    Rect faceBox, {
    required bool framesMirrored,
    String? saveJpegTo,
  }) async {
    calls.add((mirrored: framesMirrored, savedTo: saveJpegTo));
    final embedding = results.isEmpty ? _axis(0) : results.removeAt(0);
    return FaceSample(embedding: embedding, imagePath: saveJpegTo ?? '');
  }

  @override
  FaceMatchResult compare(List<double> enrolled, List<double> fresh) => _real.compare(enrolled, fresh);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

String _staffJson({String modelVersion = 'mobilefacenet-192-v1', bool templates = true}) => jsonEncode({
  'id': 'S1',
  'employee_id': 'E-1',
  'name': 'Sam',
  'enrolled': templates,
  'face_templates': templates
      ? [
          {'id': 't1', 'model_version': modelVersion, 'embedding': _axis(0)},
        ]
      : [],
});

/// A cubit wired to fakes, and a way to play a whole head-turn check into it.
class _Harness {
  _Harness({List<List<double>>? embeddings, String? staff, this.locate, this.finalFrames = 1})
    : adapter = FakeHttpAdapter()..body = staff ?? _staffJson() {
    embeddingService = _FakeEmbeddings(
      embeddings ?? [_atCos(0.95), _atCos(0.85), _atCos(0.8), _atCos(0.9)], // start, turn 1, turn 2, final
    );
    final dir = Directory.systemTemp.createTempSync('attendance_test');
    photo = File('${dir.path}/final.jpg')..writeAsBytesSync([0xFF, 0xD8, 0xFF, 0xD9]);
    final client = ApiClient()..dio.httpClientAdapter = adapter;
    camera = _FakeCamera();
    cubit = MarkAttendanceCubit(
      staffId: 'S1',
      camera: camera,
      embeddingService: embeddingService,
      staffService: StaffService(client),
      attendanceService: AttendanceService(client),
      finalFrames: finalFrames,
      framesMirrored: true,
      random: Random(1),
      locate: locate ?? () async => (latitude: 28.6139, longitude: 77.209),
      newPhotoPath: () async => photo.path,
      clock: () => now,
    );
    addTearDown(() {
      cubit.close();
      dir.deleteSync(recursive: true);
    });
  }

  final FakeHttpAdapter adapter;
  final Future<({double latitude, double longitude})> Function()? locate;
  final int finalFrames;
  late final _FakeEmbeddings embeddingService;
  late final _FakeCamera camera;
  late final File photo;
  late final MarkAttendanceCubit cubit;

  DateTime now = DateTime.utc(2026, 9, 21, 9);
  Duration observedAt = Duration.zero;
  int _i = 0;

  Future<void> start() async {
    await cubit.initializeCamera();
  }

  /// One analysed frame; poses are in person-space (turning left is a positive nose offset),
  /// with the head angle the way a real iPhone reports it (left is negative).
  void frame({double yaw = 0, double ratio = 0, bool face = true, int ms = 100}) {
    observedAt += Duration(milliseconds: ms);
    now = now.add(Duration(milliseconds: ms));
    final deviceYaw = ratio.abs() >= 0.05 ? -ratio.sign * yaw.abs() : yaw;
    final observation = face
        ? FaceObservation(
            at: observedAt,
            frameIndex: _i++,
            faceCount: 1,
            trackingId: 1,
            yawDegrees: deviceYaw,
            turnRatio: ratio,
            framing: FaceFraming.good,
            centerX: 0.5,
            centerY: 0.45,
            widthRatio: 0.5,
          )
        : FaceObservation.noFace(at: observedAt, frameIndex: _i++);
    cubit.onFrame(
      AnalyzedFrame(
        observation: observation,
        snapshot: () => CameraFrame(
          bytes: Uint8List(4),
          width: 1,
          height: 1,
          bytesPerRow: 4,
          format: FrameFormat.bgra8888,
          rotationDegrees: 0,
        ),
        faceBox: face ? const Rect.fromLTWH(0, 0, 10, 10) : null,
      ),
    );
  }

  void turn(TurnSide side, {int frames = 3}) {
    final sign = side == TurnSide.left ? 1.0 : -1.0;
    for (var i = 0; i < frames; i++) {
      frame(yaw: 20, ratio: sign * 0.25);
    }
  }

  void neutral(int frames) {
    for (var i = 0; i < frames; i++) {
      frame();
    }
  }

  /// A person doing exactly what is asked: hold still, the turns, then look straight.
  Future<void> doTheCheck() async {
    neutral(9);
    for (final side in cubit.challenge) {
      turn(side);
      frame();
    }
    neutral(8);
    await pumpEventQueue();
  }

  /// A check that fails at once: turning the wrong way after the hold.
  void failTheCheck() {
    neutral(9);
    turn(cubit.challenge.first.opposite);
  }

  /// The failed-check reports that were sent, as the JSON bodies.
  List<Map<String, Object?>> get reports => [
    for (final r in adapter.requests.where((r) => r.path == '/attendance/attempts'))
      (r.data as Map).cast<String, Object?>(),
  ];

  List<RequestOptions> get uploads => adapter.requests.where((r) => r.path == '/attendance').toList();

  Map<String, String> get uploadFields => {for (final f in (uploads.single.data as FormData).fields) f.key: f.value};
}

void main() {
  group('a person who does the check and is who they say they are', () {
    test('is recorded, with the photo, the place, the time and what the check saw', () async {
      final h = _Harness();
      await h.start();
      expect(h.cubit.state.status, MarkAttendanceStatus.cameraReady);

      await h.doTheCheck();

      expect(h.cubit.state.status, MarkAttendanceStatus.success);
      expect(h.cubit.state.similarity, closeTo(0.9, 1e-6));

      final fields = h.uploadFields;
      expect(fields['staffId'], 'S1');
      expect(fields['latitude'], '28.6139');
      expect(fields['longitude'], '77.209');
      expect(double.parse(fields['matchConfidence']!), closeTo(0.9, 1e-6));
      expect(DateTime.parse(fields['capturedAt']!).isUtc, isTrue);
      expect((h.uploads.single.data as FormData).files.single.value.filename, 'attendance.jpg');

      final liveness = jsonDecode(fields['liveness']!) as Map<String, dynamic>;
      expect(liveness['version'], 1);
      expect(liveness['challenge'], [for (final s in h.cubit.challenge) s.name]);
      expect(liveness['durationMs'], greaterThan(1000));
      expect(liveness['peakYaws'], hasLength(2));
      expect(liveness['peakTurnRatios'], hasLength(2));
      expect(liveness['sameFaceMin'], greaterThan(0.4));
    });

    test('has the frames from the check embedded, the last one saved as the photo', () async {
      final h = _Harness();
      await h.start();
      await h.doTheCheck();

      final calls = h.embeddingService.calls;
      expect(calls.length, greaterThanOrEqualTo(4), reason: 'start, two turns, final');
      expect(calls[0].savedTo, isNull);
      expect(calls[1].savedTo, isNull);
      expect(calls[2].savedTo, isNull);
      expect(calls[3].savedTo, h.photo.path, reason: 'the final straight frame becomes the attendance photo');
      expect(calls.take(4).every((c) => c.mirrored), isTrue, reason: 'the device stream is treated as mirrored');
    });

    test('takes a fresh random challenge each time, always one side then the other', () async {
      final sides = <String>{};
      for (var seed = 0; seed < 30; seed++) {
        final h = _Harness();
        // Build with a different seed each time through the public constructor path.
        final cubit = MarkAttendanceCubit(
          staffId: 'S1',
          camera: _FakeCamera(),
          embeddingService: _FakeEmbeddings([]),
          staffService: StaffService(ApiClient()..dio.httpClientAdapter = h.adapter),
          attendanceService: AttendanceService(ApiClient()..dio.httpClientAdapter = h.adapter),
          random: Random(seed),
        );
        addTearDown(cubit.close);
        expect(cubit.challenge[1], cubit.challenge[0].opposite);
        sides.add(cubit.challenge.map((side) => side.name).join(','));
      }
      expect(sides, {'left,right', 'right,left'});
    });
  });

  group('a check that passes but is not the enrolled person', () {
    test('is not recorded: the final face does not match', () async {
      final h = _Harness(embeddings: [_atCos(0.9), _atCos(0.9), _atCos(0.9), _axis(2)]);
      await h.start();
      await h.doTheCheck();

      expect(h.cubit.state.status, MarkAttendanceStatus.matchFailed);
      expect(h.cubit.state.similarity, closeTo(0, 1e-6));
      expect(h.uploads, isEmpty);
    });

    test('is not recorded: someone else did the turns and a picture of the right person is shown at the end', () async {
      // The final frame matches the enrolled face, but the frames from the turns are another person.
      final h = _Harness(embeddings: [_axis(3), _axis(3), _axis(3), _atCos(0.9)]);
      await h.start();
      await h.doTheCheck();

      expect(h.cubit.state.status, MarkAttendanceStatus.livenessFailed);
      expect(h.cubit.state.errorMessage, contains('face changed'));
      expect(h.uploads, isEmpty);
    });

    test('a person with no enrolled face is sent back with a message, not blamed', () async {
      final h = _Harness(staff: _staffJson(templates: false));
      await h.start();
      await h.doTheCheck();

      expect(h.cubit.state.status, MarkAttendanceStatus.cameraReady);
      expect(h.cubit.state.errorMessage, contains("hasn't been enrolled"));
      expect(h.uploads, isEmpty);
    });

    test('a person enrolled only with another model version is told to be re-enrolled', () async {
      final h = _Harness(staff: _staffJson(modelVersion: 'some-old-model'));
      await h.start();
      await h.doTheCheck();

      expect(h.cubit.state.errorMessage, contains('enrolled again'));
      expect(h.uploads, isEmpty);
    });
  });

  group('a check that does not pass', () {
    test('says why, and a new attempt starts with a fresh check', () async {
      final h = _Harness();
      await h.start();
      h.failTheCheck();

      expect(h.cubit.state.status, MarkAttendanceStatus.livenessFailed);
      expect(h.cubit.state.errorMessage, contains('wrong way'));

      h.cubit.retry();

      expect(h.cubit.state.status, MarkAttendanceStatus.cameraReady);
      expect(h.cubit.guidance.value.phase, LivenessPhase.waitingForFace);
    });

    test('there is no limit: many failures in a row still let the person try again', () async {
      final h = _Harness();
      await h.start();

      for (var attempt = 1; attempt <= 6; attempt++) {
        h.failTheCheck();
        expect(h.cubit.state.status, MarkAttendanceStatus.livenessFailed);
        h.cubit.retry();
        expect(h.cubit.state.status, MarkAttendanceStatus.cameraReady);
      }

      await h.doTheCheck();
      expect(h.cubit.state.status, MarkAttendanceStatus.success);
    });

    test('a success after failures is recorded as usual', () async {
      final h = _Harness();
      await h.start();
      h.failTheCheck();
      h.cubit.retry();

      await h.doTheCheck();

      expect(h.cubit.state.status, MarkAttendanceStatus.success);
    });

    test('a face that vanishes for good fails the check', () async {
      final h = _Harness();
      await h.start();
      h.neutral(9);
      h.turn(h.cubit.challenge.first, frames: 3);
      for (var i = 0; i < 12; i++) {
        h.frame(face: false);
      }

      expect(h.cubit.state.status, MarkAttendanceStatus.livenessFailed);
      expect(h.cubit.state.errorMessage, contains('lost sight'));
    });
  });

  group('trouble that is not the person\'s fault', () {
    test('a server error puts them back on a fresh check with its message, and is not counted', () async {
      final h = _Harness();
      h.adapter.body = _staffJson();
      await h.start();

      // The profile loads, then the upload fails.
      await h.cubit.initializeCamera();
      h.neutral(9);
      for (final side in h.cubit.challenge) {
        h.turn(side);
        h.frame();
      }
      h.adapter
        ..status = 500
        ..body = '{"error":"Storage is down"}';
      h.neutral(8);
      await pumpEventQueue();

      expect(h.cubit.state.status, MarkAttendanceStatus.cameraReady);
      expect(h.cubit.state.errorMessage, isNotNull);
      expect(h.uploads, isEmpty);
    });

    test('location being off explains itself and starts over', () async {
      final h = _Harness(locate: () async => throw FaceProcessingException('Location services are off.'));
      await h.start();
      await h.doTheCheck();

      expect(h.cubit.state.status, MarkAttendanceStatus.cameraReady);
      expect(h.cubit.state.errorMessage, 'Location services are off.');
      expect(h.uploads, isEmpty);
    });

    test('a location that times out asks the person to move somewhere open', () async {
      final h = _Harness(locate: () async => throw TimeoutException('gps'));
      await h.start();
      await h.doTheCheck();

      expect(h.cubit.state.errorMessage, contains('open area'));
    });

    test('a camera that will not open is an error the person can retry', () async {
      final h = _Harness();
      h.camera.failToOpen = true;
      await h.start();

      expect(h.cubit.state.status, MarkAttendanceStatus.error);
      expect(h.cubit.state.errorMessage, contains('camera'));
    });
  });

  group('frames at the wrong time', () {
    test('are ignored before the camera is ready', () async {
      final h = _Harness();
      h.neutral(12);

      expect(h.cubit.state.status, MarkAttendanceStatus.initial);
      expect(h.cubit.guidance.value.phase, LivenessPhase.waitingForFace);
    });

    test('are ignored while the person is being verified', () async {
      final h = _Harness();
      await h.start();
      h.neutral(9);
      for (final side in h.cubit.challenge) {
        h.turn(side);
        h.frame();
      }
      h.neutral(8); // the check passes here and verification starts
      expect(h.cubit.state.status, MarkAttendanceStatus.processing);

      for (var i = 0; i < 20; i++) {
        h.frame(yaw: 30, ratio: 0.5); // nonsense arriving meanwhile
      }
      await pumpEventQueue();

      expect(h.cubit.state.status, MarkAttendanceStatus.success);
      expect(h.uploads.length, 1, reason: 'recorded once');
    });
  });

  group('what the person sees', () {
    test('the guidance follows the check', () async {
      final h = _Harness();
      await h.start();
      expect(h.cubit.guidance.value.prompt, 'Look at the camera, inside the oval');

      h.neutral(9);
      final first = h.cubit.challenge.first;
      expect(h.cubit.guidance.value.prompt, 'Turn your head to the ${first.name}');
      expect(h.cubit.guidance.value.heading, 'Turn 1 of 2');
    });
  });

  group('a camera that stalls', () {
    test('cannot leave the check hanging: with no frames the check fails', () {
      fakeAsync((async) {
        final h = _Harness();
        h.cubit.initializeCamera();
        async.flushMicrotasks();
        h.neutral(9);
        h.turn(h.cubit.challenge.first, frames: 3);
        expect(h.cubit.state.status, MarkAttendanceStatus.cameraReady);

        // The camera goes quiet.
        h.now = h.now.add(const Duration(seconds: 4));
        async.elapse(const Duration(seconds: 4));

        expect(h.cubit.state.status, MarkAttendanceStatus.livenessFailed);
        expect(h.cubit.state.errorMessage, isNotNull);
      });
    });
  });

  group('failed checks are reported to the backend', () {
    test('a head-turn check that did not pass, with why', () async {
      final h = _Harness();
      await h.start();
      h.failTheCheck();
      await pumpEventQueue();

      expect(h.reports, [
        {'outcome': 'liveness_failed', 'reason': 'wrongDirection'},
      ]);
    });

    test('a face that did not match is reported as no_match, with no reason', () async {
      final h = _Harness(embeddings: [_atCos(0.9), _atCos(0.9), _atCos(0.9), _axis(2)]);
      await h.start();
      await h.doTheCheck();
      await pumpEventQueue();

      expect(h.reports, [
        {'outcome': 'no_match'},
      ]);
    });

    test('a swapped-in face is reported as a failed check, naming it', () async {
      final h = _Harness(embeddings: [_axis(3), _axis(3), _axis(3), _atCos(0.9)]);
      await h.start();
      await h.doTheCheck();
      await pumpEventQueue();

      expect(h.reports, [
        {'outcome': 'liveness_failed', 'reason': 'differentPerson'},
      ]);
    });

    test('every failure in a row is reported, and the screen stays usable', () async {
      final h = _Harness();
      await h.start();
      for (var i = 0; i < 3; i++) {
        h.failTheCheck();
        if (i < 2) h.cubit.retry();
      }
      await pumpEventQueue();

      expect(h.reports.length, 3);
      expect(h.cubit.state.status, MarkAttendanceStatus.livenessFailed);
    });

    test('a success reports nothing', () async {
      final h = _Harness();
      await h.start();
      await h.doTheCheck();
      await pumpEventQueue();

      expect(h.cubit.state.status, MarkAttendanceStatus.success);
      expect(h.reports, isEmpty);
    });

    test('trouble that is not a failed check (no enrolled face, network) reports nothing', () async {
      final h = _Harness(staff: _staffJson(templates: false));
      await h.start();
      await h.doTheCheck();
      await pumpEventQueue();

      expect(h.reports, isEmpty);
    });

    test('if the report cannot be sent, the person still sees exactly the same thing', () async {
      final h = _Harness();
      await h.start();
      h.adapter
        ..status = 500
        ..body = '{"error":"down"}';
      h.failTheCheck();
      await pumpEventQueue();

      expect(h.cubit.state.status, MarkAttendanceStatus.livenessFailed);
      expect(h.cubit.state.errorMessage, contains('wrong way'));
      expect(h.reports.length, 1, reason: 'it was attempted');
    });
  });

  group('the last few frames are averaged, because one video frame is noisy', () {
    // Results, in the order the cubit asks for them: start, turn 1, turn 2, then each final frame.
    List<List<double>> results(List<List<double>> finals) => [_atCos(0.9), _atCos(0.9), _atCos(0.9), ...finals];

    test('a bad frame among good ones does not sink the check', () async {
      // The last frame alone (orthogonal to the enrolled face) would be rejected; its four neighbours are fine.
      final finals = [_axis(0), _axis(0), _axis(0), _axis(0), _axis(2)];
      final h = _Harness(embeddings: results(finals), finalFrames: 5);
      await h.start();
      await h.doTheCheck();

      expect(h.cubit.state.status, MarkAttendanceStatus.success);
      expect(
        h.cubit.state.similarity,
        closeTo(0.8 / sqrt(0.64 + 0.04), 1e-6),
        reason: 'the average, not the last frame',
      );
    });

    test('the same bad frame on its own is rejected: this is what averaging changes', () async {
      final h = _Harness(embeddings: results([_axis(2)]), finalFrames: 1);
      await h.start();
      await h.doTheCheck();

      expect(h.cubit.state.status, MarkAttendanceStatus.matchFailed);
    });

    test('five frames are embedded, and only the last is saved as the attendance photo', () async {
      final h = _Harness(embeddings: results(List.generate(5, (_) => _atCos(0.9))), finalFrames: 5);
      await h.start();
      await h.doTheCheck();

      final primary = h.embeddingService.calls.where((c) => c.mirrored).toList();
      expect(primary.length, 3 + 5, reason: 'start, two turns, five final frames');
      expect(primary.skip(3).map((c) => c.savedTo != null), [false, false, false, false, true]);
      expect(primary.last.savedTo, h.photo.path);
    });

    test('drifting during the final hold throws away the frames from before the drift', () async {
      final h = _Harness(embeddings: results(List.generate(10, (_) => _atCos(0.9))), finalFrames: 10);
      await h.start();
      h.neutral(9);
      for (final side in h.cubit.challenge) {
        h.turn(side);
        h.frame();
      }
      h.neutral(3); // holding still: frames start to be remembered
      for (var i = 0; i < 3; i++) {
        h.frame(yaw: 15, ratio: 0.12); // drifted off straight: the hold starts over
      }
      h.neutral(8);
      await pumpEventQueue();

      final primary = h.embeddingService.calls.where((c) => c.mirrored).length;
      expect(h.cubit.state.status, MarkAttendanceStatus.success);
      expect(primary, 3 + 5, reason: 'only the five frames of the hold that finished, not the ones before the drift');
    });

    test('a face that is someone else in the final frames is still caught by the same-person check', () async {
      final h = _Harness(
        embeddings: [_axis(3), _axis(3), _axis(3), ...List.generate(5, (_) => _atCos(0.9))],
        finalFrames: 5,
      );
      await h.start();
      await h.doTheCheck();

      expect(h.cubit.state.status, MarkAttendanceStatus.livenessFailed);
      expect(h.cubit.state.errorMessage, contains('face changed'));
    });
  });
}
