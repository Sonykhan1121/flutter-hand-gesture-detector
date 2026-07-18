import 'dart:io';

import '../constants/hand_gesture_thresholds.dart';
import '../enums/object_detection_backend.dart';
import 'google_mlkit_object_detection_service.dart';
import 'native_method_channel_object_detection_service.dart';
import 'opencv_sdk_object_detection_service.dart';
import 'object_detection_package_service.dart';
import 'object_detection_service.dart';
import 'ultralytics_yolo_object_detection_service.dart';

/// Creates exactly one package-specific detector behind the shared contract.
abstract final class ObjectDetectionServiceFactory {
  static Future<ObjectDetectionService> start({
    ObjectDetectionBackend backend = ObjectDetectionBackend.ultralyticsYolo,
  }) {
    return switch (backend) {
      ObjectDetectionBackend.objectDetectionPackage =>
        ObjectDetectionPackageService.start(),
      ObjectDetectionBackend.ultralyticsYolo =>
        UltralyticsYoloObjectDetectionService.start(),
      ObjectDetectionBackend.googleMlKit =>
        GoogleMlKitObjectDetectionService.start(),
      ObjectDetectionBackend.nativeMethodChannel =>
        NativeMethodChannelObjectDetectionService.start(),
      ObjectDetectionBackend.opencvSdk =>
        OpenCvSdkObjectDetectionService.start(),
    };
  }

  /// ML Kit needs a faster stream warm-up cadence. Every service remains
  /// single-flight, so busy native detectors still drop incoming frames.
  static Duration requestMinIntervalFor({
    required ObjectDetectionBackend backend,
    bool? isIOS,
  }) {
    if (backend == ObjectDetectionBackend.googleMlKit) {
      return (isIOS ?? Platform.isIOS)
          ? HandGestureThresholds.iosGoogleMlKitObjectDetectionMinInterval
          : HandGestureThresholds.googleMlKitObjectDetectionMinInterval;
    }
    if (backend == ObjectDetectionBackend.nativeMethodChannel) {
      return HandGestureThresholds
          .nativeMethodChannelObjectDetectionMinInterval;
    }
    if (backend == ObjectDetectionBackend.opencvSdk) {
      return HandGestureThresholds.opencvSdkObjectDetectionMinInterval;
    }
    return (isIOS ?? Platform.isIOS)
        ? HandGestureThresholds.iosObjectDetectionMinInterval
        : HandGestureThresholds.objectDetectionMinInterval;
  }
}
