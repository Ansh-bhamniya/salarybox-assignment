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
  static const _inputSize = 112;
  static const _embeddingLength = 192;

  /// The crop is the detected face box, made square and this much larger so
  /// the model sees a little forehead/chin context like its training crops.
  static const _cropMargin = 1.2;

  /// Beyond this head turn (degrees) embeddings stop being reliable.
  static const _maxYawDegrees = 25.0;

  /// Longest side of the image handed to the detector and uploaded. Plenty
  /// for a face, and keeps uploads small.
  static const _maxImageSide = 1280;

  /// Extra rotations to try if the upright photo yields no face. Camera
  /// plugins occasionally hand back sideways/upside-down pixels or wrong
  /// EXIF, and ML Kit only finds faces that are (roughly) upright.
  static const _fallbackRotations = [90, 270, 180];

  Future<FaceSample> generateEmbedding(String imagePath) async {
    var prepared = await _prepareImage(imagePath);
    var faces = await _detect(prepared);

    if (faces.isEmpty) {
      for (final degrees in _fallbackRotations) {
        final rotated = await _prepareImage(imagePath, rotateDegrees: degrees);
        final rotatedFaces = await _detect(rotated);
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
    if ((face.headEulerAngleY ?? 0).abs() > _maxYawDegrees) {
      throw FaceProcessingException('Please face the camera directly, without turning your head.');
    }

    final embedding = await _embed(prepared, face.boundingBox);
    return FaceSample(embedding: embedding, imagePath: prepared);
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

    final side = min((max(width, height) * _cropMargin).floor(), min(image.width, image.height));
    final centerX = left + width / 2;
    final centerY = top + height / 2;
    final x = (centerX - side / 2).round().clamp(0, image.width - side);
    final y = (centerY - side / 2).round().clamp(0, image.height - side);

    final crop = img.copyCrop(image, x: x, y: y, width: side, height: side);
    final resized = img.copyResize(
      crop,
      width: _inputSize,
      height: _inputSize,
      interpolation: img.Interpolation.linear,
    );

    final tensor = Float32List(_inputSize * _inputSize * 3);
    var i = 0;
    for (final pixel in resized) {
      tensor[i++] = (pixel.r - 128) / 128;
      tensor[i++] = (pixel.g - 128) / 128;
      tensor[i++] = (pixel.b - 128) / 128;
    }
    return tensor;
  }

  /// Decodes the photo, applies its EXIF orientation to the actual pixels,
  /// optionally rotates it, downsizes it and writes a fresh JPEG. Runs off
  /// the UI isolate because decoding/encoding a photo is CPU heavy.
  Future<String> _prepareImage(String sourcePath, {int rotateDegrees = 0}) async {
    final dir = await getTemporaryDirectory();
    final outPath = '${dir.path}/face_${DateTime.now().microsecondsSinceEpoch}_$rotateDegrees.jpg';

    final ok = await Isolate.run(() {
      final decoded = img.decodeImage(File(sourcePath).readAsBytesSync());
      if (decoded == null) return false;

      var image = img.bakeOrientation(decoded);
      if (rotateDegrees != 0) image = img.copyRotate(image, angle: rotateDegrees);
      if (image.width > _maxImageSide || image.height > _maxImageSide) {
        image = image.width >= image.height
            ? img.copyResize(image, width: _maxImageSide)
            : img.copyResize(image, height: _maxImageSide);
      }
      File(outPath).writeAsBytesSync(img.encodeJpg(image, quality: 90));
      return true;
    });

    if (!ok) {
      throw FaceProcessingException('Could not read the photo. Please retake it.');
    }
    return outPath;
  }

  FaceMatchResult compare(List<double> enrolled, List<double> fresh) => compareToAny([enrolled], fresh);

  /// Compares a fresh embedding with every enrolled template and keeps the
  /// best score, so one good capture out of several is enough. No templates
  /// never matches.
  FaceMatchResult compareToAny(List<List<double>> enrolled, List<double> fresh) {
    var best = 0.0;
    for (var i = 0; i < enrolled.length; i++) {
      final similarity = _cosineSimilarity(enrolled[i], fresh);
      if (i == 0 || similarity > best) best = similarity;
    }
    if (!kReleaseMode) {
      debugPrint(
        '[face] similarity=${best.toStringAsFixed(3)} (best of ${enrolled.length}) threshold=${Env.faceMatchThreshold}',
      );
    }
    return FaceMatchResult(isMatch: enrolled.isNotEmpty && best >= Env.faceMatchThreshold, similarity: best);
  }

  /// Different lengths (e.g. an enrolment made before this model existed)
  /// score 0, so they can never match — the person just needs re-enrolling.
  double _cosineSimilarity(List<double> a, List<double> b) {
    if (a.length != b.length || a.isEmpty) return 0;

    double dot = 0, normA = 0, normB = 0;
    for (var i = 0; i < a.length; i++) {
      dot += a[i] * b[i];
      normA += a[i] * a[i];
      normB += b[i] * b[i];
    }
    if (normA == 0 || normB == 0) return 0;
    return dot / (sqrt(normA) * sqrt(normB));
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
