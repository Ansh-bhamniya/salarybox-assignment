import 'dart:io';
import 'dart:typed_data';
import 'dart:math';
import 'package:camera/camera.dart';
import 'package:dio/dio.dart' show FormData;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/bloc/face_capture/face_capture_cubit.dart';
import 'package:frontend/bloc/face_capture/face_capture_state.dart';
import 'package:frontend/bloc/face_enrolment/face_enrolment_cubit.dart';
import 'package:frontend/bloc/face_enrolment/face_enrolment_state.dart';
import 'package:frontend/models/duplicate_match.dart';
import 'package:frontend/models/face_match_result.dart';
import 'package:frontend/screen/face_enrolment/enrolment_dialogs.dart';
import 'package:frontend/services/camera_capture_controller.dart';
import 'package:frontend/services/face_embedding_service.dart';
import 'package:frontend/services/liveness/enrolment_pose_guide.dart';
import 'package:frontend/services/liveness/camera_frame.dart';
import 'package:frontend/services/liveness/face_observation.dart';
import 'package:frontend/services/liveness/liveness_analyzer.dart';
import 'package:frontend/services/staff_service.dart';
import 'package:frontend/utils/http/api_client.dart';
import 'helpers/fake_http_adapter.dart';

/// A unit vector whose cosine similarity with [_axis] 0 is [cos].
List<double> _atCos(double cos) => List<double>.filled(192, 0)
  ..[0] = cos
  ..[1] = sqrt(1 - cos * cos);

class _FakeCamera implements CameraCaptureController {
  var captures = 0;
  var disposed = false;

  @override
  Future<void> initialize() async {}

  @override
  Future<XFile> capture() async => XFile('/tmp/photo_${captures++}.jpg');

  @override
  Future<void> dispose() async => disposed = true;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Hands out canned results in order; comparison is the real thing.
class _FakeEmbeddings implements FaceEmbeddingService {
  _FakeEmbeddings(this.results);

  final List<Object> results; // a FaceSample, or an exception to throw
  final _real = FaceEmbeddingService();

  @override
  Future<FaceSample> generateEmbedding(String imagePath, {double maxYawDegrees = 25}) async {
    final next = results.removeAt(0);
    if (next is Exception) throw next;
    return next as FaceSample;
  }

  /// What [embedFrame] hands out, in order (an exception is thrown); empty means "not available".
  final List<Object> frameResults = [];
  var framesEmbedded = 0;

  @override
  Future<FaceSample> embedFrame(
    CameraFrame frame,
    Rect faceBox, {
    required bool framesMirrored,
    String? saveJpegTo,
  }) async {
    framesEmbedded++;
    if (frameResults.isEmpty) throw UnimplementedError('no frame embeddings in this test');
    final next = frameResults.removeAt(0);
    if (next is Exception) throw next;
    return FaceSample(embedding: next as List<double>, imagePath: '');
  }

  @override
  FaceMatchResult compare(List<double> enrolled, List<double> fresh) => _real.compare(enrolled, fresh);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

FaceSample _shot(double cosWithFirst, [String path = '/tmp/x.jpg', double? yaw]) =>
    FaceSample(embedding: _atCos(cosWithFirst), imagePath: path, yawDegrees: yaw);

/// One analysed live frame, in person-space (turning left is a positive nose offset).
FaceObservation _obs(int i, {double yaw = 0, double ratio = 0}) => FaceObservation(
  at: Duration(milliseconds: 100 * i),
  frameIndex: i,
  faceCount: 1,
  trackingId: 1,
  yawDegrees: yaw,
  turnRatio: ratio,
  centerX: 0.5,
  centerY: 0.45,
  widthRatio: 0.5,
);

void main() {
  group('FaceCaptureCubit (several photos per enrolment)', () {
    FaceCaptureCubit cubitWith(List<Object> results, {int shots = 3}) =>
        FaceCaptureCubit(_FakeCamera(), _FakeEmbeddings(results), targetShots: shots);

    test('collects the photos in order and finishes on the last one', () async {
      final cubit = cubitWith([_shot(1, '/a.jpg'), _shot(0.8, '/b.jpg'), _shot(0.7, '/c.jpg')]);
      addTearDown(cubit.close);

      await cubit.captureAndProcess();
      expect(cubit.state.status, FaceCaptureStatus.cameraReady);
      expect(cubit.state.shots.length, 1);

      await cubit.captureAndProcess();
      expect(cubit.state.status, FaceCaptureStatus.cameraReady);
      expect(cubit.state.shots.length, 2);

      await cubit.captureAndProcess();
      expect(cubit.state.status, FaceCaptureStatus.ready);
      expect(cubit.state.shots.map((s) => s.imagePath), ['/a.jpg', '/b.jpg', '/c.jpg']);
    });

    test('a later photo of a different person is rejected and not kept', () async {
      // 0.1 against the first photo is far below the same-person sanity check.
      final cubit = cubitWith([_shot(1, '/a.jpg'), _shot(0.1, '/other.jpg')]);
      addTearDown(cubit.close);

      await cubit.captureAndProcess();
      await cubit.captureAndProcess();

      expect(cubit.state.status, FaceCaptureStatus.cameraReady);
      expect(cubit.state.shots.map((s) => s.imagePath), ['/a.jpg']);
      expect(cubit.state.errorMessage, contains('same person'));
    });

    test('a photo with no usable face keeps what was captured and explains why', () async {
      final cubit = cubitWith([_shot(1, '/a.jpg'), FaceProcessingException('No face detected.')]);
      addTearDown(cubit.close);

      await cubit.captureAndProcess();
      await cubit.captureAndProcess();

      expect(cubit.state.status, FaceCaptureStatus.cameraReady);
      expect(cubit.state.shots.length, 1);
      expect(cubit.state.errorMessage, 'No face detected.');
    });

    test('an unexpected failure is reported without losing earlier photos', () async {
      final cubit = cubitWith([_shot(1, '/a.jpg'), StateError('boom')]);
      addTearDown(cubit.close);

      await cubit.captureAndProcess();
      await cubit.captureAndProcess();

      expect(cubit.state.shots.length, 1);
      expect(cubit.state.errorMessage, contains('Something went wrong'));
    });

    test('retake throws every photo away and starts over', () async {
      final cubit = cubitWith([_shot(1), _shot(0.8)]);
      addTearDown(cubit.close);
      await cubit.captureAndProcess();
      await cubit.captureAndProcess();

      cubit.retake();

      expect(cubit.state.status, FaceCaptureStatus.cameraReady);
      expect(cubit.state.shots, isEmpty);
    });

    test('the number of photos is configurable', () async {
      final cubit = cubitWith([_shot(1)], shots: 1);
      addTearDown(cubit.close);

      await cubit.captureAndProcess();

      expect(cubit.state.status, FaceCaptureStatus.ready);
    });
  });

  group('FaceCaptureCubit (templates from the live stream)', () {
    const box = Rect.fromLTWH(100, 100, 300, 400);
    final picture = CameraFrame(
      bytes: Uint8List(16),
      width: 2,
      height: 2,
      bytesPerRow: 8,
      format: FrameFormat.bgra8888,
      rotationDegrees: 0,
    );

    AnalyzedFrame frame(int i, {double yaw = 0, double ratio = 0}) => AnalyzedFrame(
      observation: _obs(i, yaw: yaw, ratio: ratio),
      snapshot: () => picture,
      faceBox: box,
    );

    /// Feeds straight frames until the first photo has been taken; returns the cubit, its embeddings and camera.
    Future<(FaceCaptureCubit, _FakeEmbeddings, _FakeCamera)> firstPhoto({
      int streamFrames = 5,
      List<Object> frames = const [],
    }) async {
      final camera = _FakeCamera();
      final embeddings = _FakeEmbeddings([_shot(1, '/still.jpg', 2)])..frameResults.addAll(frames);
      final cubit = FaceCaptureCubit(camera, embeddings, streamFrames: streamFrames, framesMirrored: true);
      addTearDown(cubit.close);
      await cubit.initializeCamera();
      for (var i = 0; i < 40 && camera.captures == 0; i++) {
        cubit.onFrame(frame(i));
      }
      await pumpEventQueue();
      return (cubit, embeddings, camera);
    }

    test('the photo is stored with the average of the last frames of the hold, not the still\'s embedding', () async {
      final (cubit, embeddings, _) = await firstPhoto(
        frames: [_atCos(0.9), _atCos(0.9), _atCos(0.9), _atCos(0.9), _atCos(0.9)],
      );

      expect(cubit.state.shots.length, 1);
      final shot = cubit.state.shots.single;
      expect(embeddings.framesEmbedded, 5);
      expect(shot.imagePath, '/still.jpg', reason: 'the still is still the photo that is uploaded');
      expect(shot.yawDegrees, 2);
      expect(shot.embedding, isNot(_atCos(1)));
      expect(shot.embedding[0], closeTo(0.9, 1e-9));
    });

    test('only the last few frames of a long hold are used', () async {
      final (_, embeddings, _) = await firstPhoto(streamFrames: 3, frames: [_atCos(0.9), _atCos(0.9), _atCos(0.9)]);

      expect(embeddings.framesEmbedded, 3);
    });

    test('with no frame pictures (or no frames wanted) the still\'s embedding is kept', () async {
      final camera = _FakeCamera();
      final embeddings = _FakeEmbeddings([_shot(1, '/still.jpg', 2)]);
      final cubit = FaceCaptureCubit(camera, embeddings, streamFrames: 0, framesMirrored: true);
      addTearDown(cubit.close);
      await cubit.initializeCamera();
      for (var i = 0; i < 40 && camera.captures == 0; i++) {
        cubit.onFrame(frame(i));
      }
      await pumpEventQueue();

      expect(embeddings.framesEmbedded, 0);
      expect(cubit.state.shots.single.embedding, _atCos(1));
    });

    test('if the frames cannot be embedded the enrolment goes on with the still', () async {
      final (cubit, _, _) = await firstPhoto(frames: [StateError('boom')]);

      expect(cubit.state.shots.length, 1);
      expect(cubit.state.shots.single.embedding, _atCos(1));
      expect(cubit.state.errorMessage, isNull);
    });

    test('frames from before the person moved are not used', () async {
      final camera = _FakeCamera();
      final embeddings = _FakeEmbeddings([_shot(1, '/still.jpg', 2)])
        ..frameResults.addAll(List.generate(5, (_) => _atCos(0.9)));
      final cubit = FaceCaptureCubit(camera, embeddings, framesMirrored: true);
      addTearDown(cubit.close);
      await cubit.initializeCamera();

      var i = 0;
      for (; i < 8; i++) {
        cubit.onFrame(frame(i)); // steady for a while...
      }
      cubit.onFrame(frame(i++, yaw: 30, ratio: 0.5)); // ...then off to the side: the hold is broken
      cubit.onFrame(frame(i++, yaw: 30, ratio: 0.5));
      for (; i < 60 && camera.captures == 0; i++) {
        cubit.onFrame(frame(i));
      }
      await pumpEventQueue();

      // Five frames, all from the second steady hold.
      expect(embeddings.framesEmbedded, 5);
      expect(camera.captures, 1);
    });
  });

  group('FaceCaptureCubit (photos taken by themselves)', () {
    late _FakeCamera camera;

    /// A ready cubit whose photos come out with the given results.
    Future<FaceCaptureCubit> ready(List<Object> results) async {
      camera = _FakeCamera();
      final cubit = FaceCaptureCubit(camera, _FakeEmbeddings(results));
      addTearDown(cubit.close);
      await cubit.initializeCamera();
      return cubit;
    }

    /// Feeds frames of one pose until the camera has fired [photos] times (or gives up).
    int feed(FaceCaptureCubit cubit, int from, {double yaw = 0, double ratio = 0, int photos = 1}) {
      var i = from;
      while (camera.captures < photos && i < from + 40) {
        cubit.onObservation(_obs(i++, yaw: yaw, ratio: ratio));
      }
      return i;
    }

    test('takes the first photo by itself once the face is held straight', () async {
      final cubit = await ready([_shot(1, '/a.jpg', 2)]);

      feed(cubit, 1);
      await pumpEventQueue();

      expect(camera.captures, 1);
      expect(cubit.state.shots.map((s) => s.imagePath), ['/a.jpg']);
      expect(cubit.state.status, FaceCaptureStatus.cameraReady);
    });

    test('nothing is taken while the person is not in position', () async {
      final cubit = await ready([_shot(1)]);

      for (var i = 1; i < 30; i++) {
        cubit.onObservation(_obs(i, yaw: 20, ratio: 0.3)); // turned, but asked to look straight
      }
      await pumpEventQueue();

      expect(camera.captures, 0);
    });

    test('never fires twice for the same photo, however many frames arrive while it is being taken', () async {
      final cubit = await ready([_shot(1, '/a.jpg', 2), _shot(1, '/b.jpg', 2)]);

      // Far more frames than the hold needs, all before the first photo finishes.
      for (var i = 1; i < 60; i++) {
        cubit.onObservation(_obs(i));
      }
      await pumpEventQueue();

      expect(camera.captures, 1);
    });

    test('moves on to the next pose after a photo is accepted, and says so', () async {
      final cubit = await ready([_shot(1, '/a.jpg', 2)]);
      expect(cubit.guidance.value.prompt, 'Look straight at the camera');

      feed(cubit, 1);
      await pumpEventQueue();

      expect(cubit.guidance.value.prompt, 'Turn your head to the left');
      expect(cubit.guidance.value.shotIndex, 1);
    });

    test('a photo where the person had moved is refused and retaken by itself', () async {
      // The first frame of the straight pose was fine, but the photo shows 20° of turn.
      final cubit = await ready([_shot(1, '/moved.jpg', 20), _shot(1, '/good.jpg', 3)]);

      var i = feed(cubit, 1);
      await pumpEventQueue();
      expect(cubit.state.shots, isEmpty);
      expect(cubit.state.errorMessage, contains('moved'));
      expect(cubit.guide.pose, EnrolmentPose.straight, reason: 'still asking for the straight photo');

      i = feed(cubit, i, photos: 2);
      await pumpEventQueue();
      expect(camera.captures, 2);
      expect(cubit.state.shots.map((s) => s.imagePath), ['/good.jpg']);
    });

    test('three photos by themselves complete the enrolment', () async {
      final cubit = await ready([_shot(1, '/1.jpg', 2), _shot(0.8, '/2.jpg', 20), _shot(0.7, '/3.jpg', -20)]);

      var i = feed(cubit, 1);
      await pumpEventQueue();
      i = feed(cubit, i, yaw: 20, ratio: 0.25, photos: 2);
      await pumpEventQueue();
      expect(cubit.state.status, FaceCaptureStatus.cameraReady);
      expect(cubit.guidance.value.prompt, 'Turn your head to the right');

      feed(cubit, i, yaw: 20, ratio: -0.25, photos: 3);
      await pumpEventQueue();

      expect(cubit.state.status, FaceCaptureStatus.ready);
      expect(cubit.state.shots.map((s) => s.imagePath), ['/1.jpg', '/2.jpg', '/3.jpg']);
      expect(cubit.guide.isComplete, isTrue);
    });

    test('a turn photo of a different person is refused like any other', () async {
      final cubit = await ready([_shot(1, '/1.jpg', 2), _shot(0.1, '/other.jpg', 20)]);

      var i = feed(cubit, 1);
      await pumpEventQueue();
      feed(cubit, i, yaw: 20, ratio: 0.25, photos: 2);
      await pumpEventQueue();

      expect(cubit.state.shots.length, 1);
      expect(cubit.state.errorMessage, contains('same person'));
      expect(cubit.guide.pose, EnrolmentPose.left, reason: 'the left turn is asked for again');
    });

    test('retake starts the whole enrolment over from the straight photo', () async {
      final cubit = await ready([_shot(1, '/1.jpg', 2)]);
      feed(cubit, 1);
      await pumpEventQueue();
      expect(cubit.guide.pose, EnrolmentPose.left);

      cubit.retake();

      expect(cubit.state.shots, isEmpty);
      expect(cubit.guide.pose, EnrolmentPose.straight);
      expect(cubit.guidance.value.prompt, 'Look straight at the camera');
    });

    test('frames arriving before the camera is ready are ignored', () async {
      camera = _FakeCamera();
      final cubit = FaceCaptureCubit(camera, _FakeEmbeddings([_shot(1)]));
      addTearDown(cubit.close);

      for (var i = 1; i < 30; i++) {
        cubit.onObservation(_obs(i));
      }

      expect(camera.captures, 0);
    });
  });

  group('FaceEnrolmentCubit', () {
    late FakeHttpAdapter adapter;
    late FaceEnrolmentCubit cubit;
    late List<FaceSample> shots;

    setUp(() {
      adapter = FakeHttpAdapter();
      cubit = FaceEnrolmentCubit(StaffService(ApiClient()..dio.httpClientAdapter = adapter));
      final dir = Directory.systemTemp.createTempSync('enrol_test');
      addTearDown(() => dir.deleteSync(recursive: true));
      final photo = File('${dir.path}/a.jpg')..writeAsBytesSync([0xFF, 0xD8, 0xFF, 0xD9]);
      shots = [
        FaceSample(embedding: [1.0], imagePath: photo.path),
      ];
    });
    tearDown(() => cubit.close());

    test('saves the enrolment', () async {
      adapter.body = '{"id":"1","employee_id":"E-1","name":"Sam","enrolled":true}';

      await cubit.submit(staffId: '1', shots: shots);

      expect(cubit.state.status, FaceEnrolmentSubmitStatus.success);
    });

    test('a face that already belongs to someone else is reported with who it looks like', () async {
      adapter
        ..status = 409
        ..body =
            '{"error":"This face looks like an already enrolled staff member","code":"duplicate_face",'
            '"details":{"matches":[{"staffId":"9","employeeId":"E-9","name":"Ravi Kumar","similarity":0.83}]}}';

      await cubit.submit(staffId: '1', shots: shots);

      expect(cubit.state.status, FaceEnrolmentSubmitStatus.duplicateFound);
      expect(cubit.state.duplicates.single.name, 'Ravi Kumar');
      expect(cubit.state.duplicates.single.employeeId, 'E-9');
      expect(cubit.state.duplicates.single.similarity, 0.83);
    });

    test('dismissing the duplicate warning returns to the review screen state', () async {
      adapter
        ..status = 409
        ..body = '{"error":"dup","code":"duplicate_face","details":{"matches":[]}}';
      await cubit.submit(staffId: '1', shots: shots);

      cubit.dismissDuplicate();

      expect(cubit.state.status, FaceEnrolmentSubmitStatus.idle);
      expect(cubit.state.duplicates, isEmpty);
    });

    test('enrolling anyway sends the override and the reason', () async {
      adapter.body = '{"id":"1","employee_id":"E-1","name":"Sam","enrolled":true}';

      await cubit.submit(staffId: '1', shots: shots, reason: 'Twins', allowDuplicate: true);

      final fields = {for (final f in (adapter.request.data as FormData).fields) f.key: f.value};
      expect(fields['allowDuplicate'], 'true');
      expect(fields['reason'], 'Twins');
      expect(cubit.state.status, FaceEnrolmentSubmitStatus.success);
    });

    test('any other backend error is shown as an error with its message', () async {
      adapter
        ..status = 400
        ..body = '{"error":"embedding must have 192 values"}';

      await cubit.submit(staffId: '1', shots: shots);

      expect(cubit.state.status, FaceEnrolmentSubmitStatus.error);
      expect(cubit.state.errorMessage, 'embedding must have 192 values');
    });
  });

  group('enrolment dialogs', () {
    Future<void> pumpOpener(
      WidgetTester tester,
      Future<Object?> Function(BuildContext) open,
      void Function(Object?) onResult,
    ) {
      return tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: TextButton(onPressed: () async => onResult(await open(context)), child: const Text('open')),
              ),
            ),
          ),
        ),
      );
    }

    testWidgets('re-enrol reason: lists the reasons and returns the one picked', (tester) async {
      Object? result = 'unset';
      await pumpOpener(tester, askReEnrolReason, (r) => result = r);

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      for (final reason in reEnrolReasons) {
        expect(find.text(reason), findsOneWidget);
      }

      await tester.tap(find.text('Recognition keeps failing'));
      await tester.pumpAndSettle();
      expect(result, 'Recognition keeps failing');
    });

    testWidgets('re-enrol reason: dismissing without a choice returns null', (tester) async {
      Object? result = 'unset';
      await pumpOpener(tester, askReEnrolReason, (r) => result = r);

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.tapAt(const Offset(5, 5)); // the barrier
      await tester.pumpAndSettle();

      expect(result, isNull);
    });

    final matches = [const DuplicateMatch(name: 'Ravi Kumar', employeeId: 'E-9', similarity: 0.834)];

    testWidgets('duplicate warning: names who it looks like and needs a reason to go ahead', (tester) async {
      Object? result = 'unset';
      await pumpOpener(tester, (c) => confirmDuplicate(c, matches), (r) => result = r);

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(find.text('Ravi Kumar (E-9) — 83% similar'), findsOneWidget);
      FilledButton enrolAnyway() => tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Enrol anyway'));
      expect(enrolAnyway().onPressed, isNull, reason: 'no reason yet');

      await tester.enterText(find.byType(TextField), '   ');
      await tester.pump();
      expect(enrolAnyway().onPressed, isNull, reason: 'blank is not a reason');

      await tester.enterText(find.byType(TextField), '  Identical twins  ');
      await tester.pump();
      expect(enrolAnyway().onPressed, isNotNull);

      await tester.tap(find.widgetWithText(FilledButton, 'Enrol anyway'));
      await tester.pumpAndSettle();
      expect(result, 'Identical twins');
    });

    testWidgets('duplicate warning: cancel returns null', (tester) async {
      Object? result = 'unset';
      await pumpOpener(tester, (c) => confirmDuplicate(c, matches), (r) => result = r);

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(result, isNull);
    });
  });
}
