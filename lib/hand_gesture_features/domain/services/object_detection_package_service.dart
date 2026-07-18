import 'dart:io';

import 'package:camera/camera.dart';
import 'package:object_detection/object_detection.dart' as od;

import '../constants/hand_gesture_thresholds.dart';
import '../enums/object_detection_backend.dart';
import '../models/app_object_detection.dart';
import 'object_detection_service.dart';

/// EfficientDet implementation supplied by the `object_detection` package.
final class ObjectDetectionPackageService
    extends SingleFlightObjectDetectionService {
  ObjectDetectionPackageService._(this._detector);

  final od.ObjectDetector _detector;

  @override
  ObjectDetectionBackend get backend =>
      ObjectDetectionBackend.objectDetectionPackage;

  static const _defaultOptions = od.ObjectDetectorOptions(
    scoreThreshold: HandGestureThresholds.objectDetectionPackageScoreThreshold,
    maxResults: HandGestureThresholds.objectDetectionMaxResults,
  );
  static const _iosOptions = od.ObjectDetectorOptions(
    scoreThreshold:
        HandGestureThresholds.iosObjectDetectionPackageScoreThreshold,
    maxResults: HandGestureThresholds.objectDetectionMaxResults,
    categoryDenylist: ['person'],
  );

  static Future<ObjectDetectionPackageService> start() async {
    final detector = await od.ObjectDetector.create(
      model: packageModelForPlatform(isIOS: Platform.isIOS),
    );
    return ObjectDetectionPackageService._(detector);
  }

  static od.ObjectDetectionModel packageModelForPlatform({
    required bool isIOS,
  }) {
    return isIOS
        ? od.ObjectDetectionModel.efficientDetLite0
        : od.ObjectDetectionModel.efficientDetLite2;
  }

  static od.ObjectDetectorOptions packageOptionsForPlatform({
    required bool isIOS,
  }) {
    return isIOS ? _iosOptions : _defaultOptions;
  }

  static int packageMaxDimensionForPlatform({required bool isIOS}) {
    return isIOS
        ? HandGestureThresholds.iosObjectDetectionMaxDimension
        : HandGestureThresholds.objectDetectionMaxDimension;
  }

  @override
  Future<List<AppObjectDetection>> performDetection(
    CameraImage image, {
    od.CameraFrameRotation? rotation,
    CameraLensDirection? lensDirection,
  }) async {
    final isIOS = Platform.isIOS;
    final objects = await _detector.detectFromCameraImage(
      image,
      rotation: rotation,
      isBgra: Platform.isIOS || Platform.isMacOS,
      maxDim: packageMaxDimensionForPlatform(isIOS: isIOS),
      options: packageOptionsForPlatform(isIOS: isIOS),
    );

    return [
      for (final object in objects)
        if (!AppObjectDetection.isPersonLabel(object.categoryName))
          AppObjectDetection.fromDetectedObject(object),
    ];
  }

  @override
  Future<void> disposeBackend() => _detector.dispose();
}
