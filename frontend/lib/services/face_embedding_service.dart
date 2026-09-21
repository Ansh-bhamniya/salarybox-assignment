import 'dart:io';
import 'dart:isolate';
import 'dart:math';
import 'dart:ui' show Rect;
import 'package:flutter/foundation.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';
import 'package:tflite_flutter/tflite_flutter.dart';
import '../config/env.dart';
import '../models/face_match_result.dart';
import './camera_frame_converter.dart';
import './face_similarity.dart';
import './liveness/camera_frame.dart';

/// Turns a selfie into a 192-number face "embedding" and compares two
/// embeddings for a match. Everything runs on-device.
///
/// Pipeline: ML Kit finds the face → the face is cropped and resized to
/// 112x112 → a bundled MobileFaceNet TFLite model
/// (`assets/models/mobilefacenet.tflite`, see the README next to it) maps the
/// crop to a unit-length vector. Two photos of the same person land close
/// together (high cosine similarity); different people land far apart.
class FaceEmbeddingService {
  final FaceDetector _detector = FaceDetector(options: FaceDetectorOptions(performanceMode: FaceDetectorMode.accurate));

  Future<Interpreter>? _interpreterFuture;

  static const _modelAsset = 'assets/models/mobilefacenet.tflite';
  static const _inputSize = faceInputSize;
  static const _embeddingLength = 192;

  /// Beyond this head turn (degrees) embeddings stop being reliable.
  static const _maxYawDegrees = 25.0;

  /// Longest side of the image handed to the detector and uploaded. Plenty
  /// for a face, and keeps uploads small.
  static const _maxImageSide = 1280;

  /// Extra rotations to try if the upright photo yields no face. Camera
  /// plugins occasionally hand back sideways/upside-down pixels or wrong
  /// EXIF, and ML Kit only finds faces that are (roughly) upright.
  static const _fallbackRotations = [90, 270, 180];

  /// [maxYawDegrees] is how far round the head may be before the photo is refused;
  /// straight-on photos use the default, deliberately turned ones allow more.
  Future<FaceSample> generateEmbedding(String imagePath, {double maxYawDegrees = _maxYawDegrees}) async {
    var prepared = await _prepareImage(imagePath);
    var faces = await _detect(prepared.path);

    if (faces.isEmpty) {
      for (final degrees in _fallbackRotations) {
        final rotated = await _prepareImage(imagePath, rotateDegrees: degrees);
        final rotatedFaces = await _detect(rotated.path);
        if (rotatedFaces.isNotEmpty) {
          prepared = rotated;
          faces = rotatedFaces;
          break;
        }
      }
    }

    if (faces.isEmpty) {
      throw FaceProcessingException(
        'No face detected. Keep your whole face inside the oval, face the camera and make sure the light is on your face.',
      );
    }
    if (faces.length > 1) {
      throw FaceProcessingException('Multiple faces detected. Only one person should be in frame.');
    }

    final face = faces.single;
    if ((face.headEulerAngleY ?? 0).abs() > maxYawDegrees) {
      throw FaceProcessingException(
        maxYawDegrees > _maxYawDegrees
            ? 'You turned a little too far. Turn back slightly.'
            : 'Please face the camera directly, without turning your head.',
      );
    }

    final embedding = await _embed(prepared.path, face.boundingBox);
    final box = face.boundingBox;
    return FaceSample(
      embedding: embedding,
      imagePath: prepared.path,
      yawDegrees: face.headEulerAngleY,
      faceCenterX: box.center.dx / prepared.width,
      faceCenterY: box.center.dy / prepared.height,
      faceWidthRatio: box.width / prepared.width,
    );
  }

  Future<List<Face>> _detect(String path) async {
    final faces = await _detector.processImage(InputImage.fromFilePath(path));
    if (!kReleaseMode) debugPrint('[face] detect ${path.split('/').last}: ${faces.length} face(s)');
    return faces;
  }

  Future<Interpreter> _loadInterpreter() async {
    try {
      return await (_interpreterFuture ??= Interpreter.fromAsset(_modelAsset));
    } catch (_) {
      _interpreterFuture = null; // allow a retry instead of caching the failure
      rethrow;
    }
  }

  Future<List<double>> _embed(String imagePath, Rect box) async {
    final left = box.left, top = box.top, width = box.width, height = box.height;
    final input = await Isolate.run(() => _buildInputTensor(imagePath, left, top, width, height));
    return _embedTensor(input);
  }

  /// The face in one frame of the live camera stream, embedded the same way as a
  /// photo. [faceBox] is where ML Kit found the face on that frame, and
  /// [framesMirrored] says whether the device's stream is mirrored (the frame is
  /// then flipped back, so it faces the same way as the enrolment photos). The
  /// whole upright picture is saved to [saveJpegTo] if given, for use as the
  /// attendance photo; otherwise the sample has no image path.
  Future<FaceSample> embedFrame(
    CameraFrame frame,
    Rect faceBox, {
    required bool framesMirrored,
    String? saveJpegTo,
  }) async {
    final crop = await cropFrameForEmbedding(frame, faceBox, mirrored: framesMirrored, saveJpegTo: saveJpegTo);
    final embedding = await _embedTensor(crop.tensor);
    return FaceSample(embedding: embedding, imagePath: crop.jpegPath ?? '');
  }

  Future<List<double>> _embedTensor(Float32List input) async {
    final interpreter = await _loadInterpreter();
    final output = List.generate(1, (_) => List.filled(_embeddingLength, 0.0));
    interpreter.run(input.reshape([1, _inputSize, _inputSize, 3]), output);

    // The model already emits a unit vector; normalizing again is cheap
    // insurance that cosine similarity below is always a proper cosine.
    final raw = List<double>.from(output[0]);
    final norm = sqrt(raw.fold<double>(0, (sum, v) => sum + v * v));
    if (norm == 0 || !norm.isFinite) {
      throw FaceProcessingException('Could not read your face clearly. Please retake the selfie.');
    }
    return raw.map((v) => v / norm).toList();
  }

  /// Crops a square around the face, resizes to the model's input size and
  /// scales pixels to roughly [-1, 1] (RGB, `(p - 128) / 128`), the way the
  /// model was trained. Static so it can run in a background isolate.
  static Float32List _buildInputTensor(String path, double left, double top, double width, double height) {
    final image = img.decodeImage(File(path).readAsBytesSync())!;
    return faceTensorFromImage(image, left, top, width, height);
  }

  /// Decodes the photo, applies its EXIF orientation to the actual pixels,
  /// optionally rotates it, downsizes it and writes a fresh JPEG. Runs off
  /// the UI isolate because decoding/encoding a photo is CPU heavy.
  Future<({String path, int width, int height})> _prepareImage(String sourcePath, {int rotateDegrees = 0}) async {
    final dir = await getTemporaryDirectory();
    final outPath = '${dir.path}/face_${DateTime.now().microsecondsSinceEpoch}_$rotateDegrees.jpg';

    final size = await Isolate.run(() {
      final decoded = img.decodeImage(File(sourcePath).readAsBytesSync());
      if (decoded == null) return null;

      var image = img.bakeOrientation(decoded);
      if (rotateDegrees != 0) image = img.copyRotate(image, angle: rotateDegrees);
      if (image.width > _maxImageSide || image.height > _maxImageSide) {
        image = image.width >= image.height
            ? img.copyResize(image, width: _maxImageSide)
            : img.copyResize(image, height: _maxImageSide);
      }
      File(outPath).writeAsBytesSync(img.encodeJpg(image, quality: 90));
      return (width: image.width, height: image.height);
    });

    if (size == null) {
      throw FaceProcessingException('Could not read the photo. Please retake it.');
    }
    return (path: outPath, width: size.width, height: size.height);
  }

  FaceMatchResult compare(List<double> enrolled, List<double> fresh) => compareToAny([enrolled], fresh);

  /// Compares a fresh embedding with every enrolled template and keeps the
  /// best score, so one good capture out of several is enough. No templates
  /// never matches.
  FaceMatchResult compareToAny(List<List<double>> enrolled, List<double> fresh) {
    var best = 0.0;
    for (var i = 0; i < enrolled.length; i++) {
      final similarity = cosineSimilarity(enrolled[i], fresh);
      if (i == 0 || similarity > best) best = similarity;
    }
    if (!kReleaseMode) {
      debugPrint(
        '[face] similarity=${best.toStringAsFixed(3)} (best of ${enrolled.length}) threshold=${Env.faceMatchThreshold}',
      );
    }
    return FaceMatchResult(isMatch: enrolled.isNotEmpty && best >= Env.faceMatchThreshold, similarity: best);
  }

  Future<void> dispose() async {
    await _detector.close();
    final interpreter = _interpreterFuture;
    _interpreterFuture = null;
    if (interpreter != null) {
      try {
        (await interpreter).close();
      } catch (_) {}
    }
  }
}
