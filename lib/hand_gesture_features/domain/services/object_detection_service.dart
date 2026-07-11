import 'dart:io';

import 'package:camera/camera.dart';
import 'package:object_detection/object_detection.dart' as od;

import '../constants/hand_gesture_thresholds.dart';
import '../models/app_object_detection.dart';

/// App wrapper around the `object_detection` package.
class ObjectDetectionService {
  ObjectDetectionService._(this._detector);

  final od.ObjectDetector _detector;

  var _isBusy = false;
  var _isClosed = false;

  bool get isBusy => _isBusy;

  static const _options = od.ObjectDetectorOptions(
    scoreThreshold: HandGestureThresholds.objectDetectionScoreThreshold,
    maxResults: HandGestureThresholds.objectDetectionMaxResults,
  );

  /// Uses Lite2 for better boxes; switch to Lite0 later if device FPS is low.
  static Future<ObjectDetectionService> start() async {
    final detector = await od.ObjectDetector.create(
      model: od.ObjectDetectionModel.efficientDetLite2,
    );
    return ObjectDetectionService._(detector);
  }

  Future<List<AppObjectDetection>> detect(
    CameraImage image, {
    od.CameraFrameRotation? rotation,
  }) async {
    if (_isClosed) return const [];
    if (_isBusy) {
      throw StateError('Object detector is busy.');
    }

    _isBusy = true;
    try {
      final objects = await _detector.detectFromCameraImage(
        image,
        rotation: rotation,
        isBgra: Platform.isIOS || Platform.isMacOS,
        maxDim: HandGestureThresholds.objectDetectionMaxDimension,
        options: _options,
      );

      return [
        for (final object in objects)
          AppObjectDetection.fromDetectedObject(object),
      ];
    } finally {
      _isBusy = false;
    }
  }

  Future<void> close() async {
    if (_isClosed) return;
    _isClosed = true;
    await _detector.dispose();
  }
}
