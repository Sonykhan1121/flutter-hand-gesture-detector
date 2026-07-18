import 'dart:io';
import 'dart:ui';

import 'package:camera/camera.dart';
import 'package:object_detection/object_detection.dart' as od;
import 'package:ultralytics_yolo/ultralytics_yolo.dart';

import '../constants/hand_gesture_thresholds.dart';
import '../enums/object_detection_backend.dart';
import '../models/app_object_detection.dart';
import 'appearance_signature_extractor.dart';
import 'object_detection_service.dart';
import 'ultralytics_yolo_model_preloader.dart';
import 'yolo_camera_frame_encoder.dart';

/// Object detector implemented only with the `ultralytics_yolo` package.
final class UltralyticsYoloObjectDetectionService
    extends SingleFlightObjectDetectionService {
  UltralyticsYoloObjectDetectionService._(
    this._yolo,
    this._modelLabels,
    this._encoder,
  );

  final YOLO _yolo;
  final List<String> _modelLabels;
  final YoloCameraFrameEncoder _encoder;

  @override
  ObjectDetectionBackend get backend => ObjectDetectionBackend.ultralyticsYolo;

  static Future<UltralyticsYoloObjectDetectionService> start() async {
    if (!Platform.isAndroid && !Platform.isIOS) {
      throw UnsupportedError(
        'Ultralytics YOLO object detection supports Android and iOS only.',
      );
    }
    final yolo = YOLO(
      modelPath: HandGestureThresholds.ultralyticsYoloModelId,
      task: YOLOTask.detect,
      useGpu: HandGestureThresholds.ultralyticsYoloUseGpu,
    );
    try {
      final metadata = await ultralyticsYoloModelPreloader.prepare();
      final loaded = await yolo.loadModel();
      if (!loaded) {
        throw StateError('Ultralytics YOLO model failed to load.');
      }
      return UltralyticsYoloObjectDetectionService._(
        yolo,
        labelsFromMetadata(metadata),
        YoloCameraFrameEncoder(
          maxDimension: maxDimensionForPlatform(isIOS: Platform.isIOS),
          jpegQuality: HandGestureThresholds.ultralyticsYoloJpegQuality,
        ),
      );
    } catch (_) {
      await yolo.dispose();
      rethrow;
    }
  }

  static int maxDimensionForPlatform({required bool isIOS}) => isIOS
      ? HandGestureThresholds.iosUltralyticsYoloMaxDimension
      : HandGestureThresholds.ultralyticsYoloMaxDimension;

  @override
  Future<List<AppObjectDetection>> performDetection(
    CameraImage image, {
    od.CameraFrameRotation? rotation,
    CameraLensDirection? lensDirection,
  }) async {
    final encoded = await _encoder.encodeInBackground(
      frame: CameraPixelFrameData.fromCameraImage(
        image,
        isBgra: Platform.isIOS || Platform.isMacOS,
      ),
      rotation: rotation,
    );
    if (encoded == null || isClosed) return const [];

    final prediction = await _yolo.predict(
      encoded.jpegBytes,
      confidenceThreshold:
          HandGestureThresholds.ultralyticsYoloConfidenceThreshold,
      iouThreshold: HandGestureThresholds.ultralyticsYoloIouThreshold,
    );
    if (isClosed) return const [];
    return mapDetections(
      prediction['boxes'] as List<dynamic>? ?? const [],
      imageSize: encoded.imageSize,
      modelLabels: _modelLabels,
    );
  }

  static List<AppObjectDetection> mapDetections(
    Iterable<dynamic> boxes, {
    required Size imageSize,
    required List<String> modelLabels,
  }) {
    if (imageSize.width <= 0 || imageSize.height <= 0) return const [];

    final normalizedLabels = [
      for (final label in modelLabels) _normalizedLabel(label),
    ];
    final results = <AppObjectDetection>[];
    for (final rawBox in boxes) {
      if (rawBox is! Map) continue;
      final label = rawBox['class']?.toString().trim() ?? '';
      final confidence = _finiteDouble(rawBox['confidence']);
      if (label.isEmpty ||
          confidence == null ||
          confidence <
              HandGestureThresholds.ultralyticsYoloConfidenceThreshold ||
          AppObjectDetection.isPersonLabel(label)) {
        continue;
      }

      final left = _finiteDouble(rawBox['x1_norm']);
      final top = _finiteDouble(rawBox['y1_norm']);
      final right = _finiteDouble(rawBox['x2_norm']);
      final bottom = _finiteDouble(rawBox['y2_norm']);
      if (left == null || top == null || right == null || bottom == null) {
        continue;
      }
      final normalizedRect = Rect.fromLTRB(
        left.clamp(0.0, 1.0),
        top.clamp(0.0, 1.0),
        right.clamp(0.0, 1.0),
        bottom.clamp(0.0, 1.0),
      );
      if (normalizedRect.isEmpty) continue;

      final classIndex = normalizedLabels.indexOf(_normalizedLabel(label));
      results.add(
        AppObjectDetection(
          boundingBox: Rect.fromLTRB(
            normalizedRect.left * imageSize.width,
            normalizedRect.top * imageSize.height,
            normalizedRect.right * imageSize.width,
            normalizedRect.bottom * imageSize.height,
          ),
          imageSize: imageSize,
          label: label,
          confidence: confidence,
          classIndex: classIndex,
          source: AppObjectDetectionSource.ultralyticsYolo,
        ),
      );
    }

    results.sort(
      (a, b) => (b.confidence ?? double.negativeInfinity).compareTo(
        a.confidence ?? double.negativeInfinity,
      ),
    );
    return List.unmodifiable(
      results.take(HandGestureThresholds.objectDetectionMaxResults),
    );
  }

  static List<String> labelsFromMetadata(Map<String, dynamic> metadata) {
    final rawLabels = metadata['labels'];
    if (rawLabels is! List) return const [];
    return List.unmodifiable(
      rawLabels
          .map((label) => label.toString().trim())
          .where((label) => label.isNotEmpty),
    );
  }

  static String _normalizedLabel(String label) => label.trim().toLowerCase();

  static double? _finiteDouble(dynamic rawValue) {
    if (rawValue is! num) return null;
    final number = rawValue.toDouble();
    return number.isFinite ? number : null;
  }

  @override
  Future<void> disposeBackend() => _yolo.dispose();
}
