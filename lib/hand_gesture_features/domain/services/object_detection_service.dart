import 'dart:async';
import 'dart:io';
import 'dart:ui';

import 'package:camera/camera.dart';
import 'package:object_detection/object_detection.dart' as od;
import 'package:ultralytics_yolo/ultralytics_yolo.dart';

import '../constants/hand_gesture_thresholds.dart';
import '../models/app_object_detection.dart';
import 'appearance_signature_extractor.dart';
import 'yolo_camera_frame_encoder.dart';

/// Stable app-facing wrapper around either supported object detector backend.
class ObjectDetectionService {
  ObjectDetectionService._package(this._packageDetector)
    : _yolo = null,
      _yoloLabels = const [],
      _yoloEncoder = null;

  ObjectDetectionService._yolo(this._yolo, this._yoloLabels, this._yoloEncoder)
    : _packageDetector = null;

  final od.ObjectDetector? _packageDetector;
  final YOLO? _yolo;
  final List<String> _yoloLabels;
  final YoloCameraFrameEncoder? _yoloEncoder;

  var _isBusy = false;
  var _isClosed = false;
  Completer<void>? _activeDetectionFinished;

  bool get isBusy => _isBusy;

  static const _packageOptions = od.ObjectDetectorOptions(
    scoreThreshold: HandGestureThresholds.objectDetectionScoreThreshold,
    maxResults: HandGestureThresholds.objectDetectionMaxResults,
  );

  /// Selects the backend through the one shared configuration flag.
  static Future<ObjectDetectionService> start() async {
    if (HandGestureThresholds.useObjectDetectionPackage) {
      final detector = await od.ObjectDetector.create(
        model: od.ObjectDetectionModel.efficientDetLite2,
      );
      return ObjectDetectionService._package(detector);
    }

    final yolo = YOLO(
      modelPath: HandGestureThresholds.ultralyticsYoloModelId,
      task: YOLOTask.detect,
      useGpu: HandGestureThresholds.ultralyticsYoloUseGpu,
    );
    try {
      final metadata = await YOLO.inspectModel(
        HandGestureThresholds.ultralyticsYoloModelId,
      );
      final loaded = await yolo.loadModel();
      if (!loaded) {
        throw StateError('Ultralytics YOLO model failed to load.');
      }
      return ObjectDetectionService._yolo(
        yolo,
        labelsFromMetadata(metadata),
        const YoloCameraFrameEncoder(
          maxDimension: HandGestureThresholds.objectDetectionMaxDimension,
          jpegQuality: HandGestureThresholds.ultralyticsYoloJpegQuality,
        ),
      );
    } catch (_) {
      await yolo.dispose();
      rethrow;
    }
  }

  Future<List<AppObjectDetection>> detect(
    CameraImage image, {
    od.CameraFrameRotation? rotation,
  }) async {
    if (_isClosed) return const [];
    if (_isBusy) throw StateError('Object detector is busy.');

    final finished = Completer<void>();
    _activeDetectionFinished = finished;
    _isBusy = true;
    try {
      final packageDetector = _packageDetector;
      if (packageDetector != null) {
        return _detectWithPackage(packageDetector, image, rotation);
      }
      final yolo = _yolo;
      final encoder = _yoloEncoder;
      if (yolo != null && encoder != null) {
        return _detectWithYolo(yolo, encoder, image, rotation);
      }
      return const [];
    } finally {
      _isBusy = false;
      if (!finished.isCompleted) finished.complete();
      if (identical(_activeDetectionFinished, finished)) {
        _activeDetectionFinished = null;
      }
    }
  }

  Future<List<AppObjectDetection>> _detectWithPackage(
    od.ObjectDetector detector,
    CameraImage image,
    od.CameraFrameRotation? rotation,
  ) async {
    final objects = await detector.detectFromCameraImage(
      image,
      rotation: rotation,
      isBgra: Platform.isIOS || Platform.isMacOS,
      maxDim: HandGestureThresholds.objectDetectionMaxDimension,
      options: _packageOptions,
    );

    return [
      for (final object in objects)
        if (!AppObjectDetection.isPersonLabel(object.categoryName))
          AppObjectDetection.fromDetectedObject(object),
    ];
  }

  Future<List<AppObjectDetection>> _detectWithYolo(
    YOLO yolo,
    YoloCameraFrameEncoder encoder,
    CameraImage image,
    od.CameraFrameRotation? rotation,
  ) async {
    final encoded = encoder.encode(
      frame: CameraPixelFrameData.fromCameraImage(
        image,
        isBgra: Platform.isIOS || Platform.isMacOS,
      ),
      rotation: rotation,
    );
    if (encoded == null || _isClosed) return const [];

    final result = await yolo.predict(
      encoded.jpegBytes,
      confidenceThreshold: HandGestureThresholds.objectDetectionScoreThreshold,
      iouThreshold: HandGestureThresholds.ultralyticsYoloIouThreshold,
    );
    if (_isClosed) return const [];
    return mapUltralyticsDetections(
      result['boxes'] as List<dynamic>? ?? const [],
      imageSize: encoded.imageSize,
      modelLabels: _yoloLabels,
    );
  }

  /// Converts the raw single-image YOLO boxes into the app detection model.
  static List<AppObjectDetection> mapUltralyticsDetections(
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
          confidence < HandGestureThresholds.objectDetectionScoreThreshold ||
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

      final normalizedLabel = _normalizedLabel(label);
      final classIndex = normalizedLabels.indexOf(normalizedLabel);
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

    results.sort((a, b) => b.confidence.compareTo(a.confidence));
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

  static double? _finiteDouble(dynamic value) {
    if (value is! num) return null;
    final result = value.toDouble();
    return result.isFinite ? result : null;
  }

  Future<void> close() async {
    if (_isClosed) return;
    _isClosed = true;
    await _activeDetectionFinished?.future;
    await _packageDetector?.dispose();
    await _yolo?.dispose();
  }
}
