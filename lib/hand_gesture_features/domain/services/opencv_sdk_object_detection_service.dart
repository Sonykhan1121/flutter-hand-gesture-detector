import 'dart:io';
import 'dart:ui';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:object_detection/object_detection.dart' as od;
import 'package:opencv_object_detection/opencv_object_detection.dart';

import '../constants/hand_gesture_thresholds.dart';
import '../enums/object_detection_backend.dart';
import '../models/app_object_detection.dart';
import 'object_detection_service.dart';

/// Object detector implemented with the native OpenCV Android Java SDK.
final class OpenCvSdkObjectDetectionService
    extends SingleFlightObjectDetectionService {
  OpenCvSdkObjectDetectionService._(this._nativeDetector);

  final OpenCvObjectDetection _nativeDetector;
  var _nextFrameId = 0;
  var _lastAcceptedFrameId = 0;

  @override
  ObjectDetectionBackend get backend => ObjectDetectionBackend.opencvSdk;

  static Future<OpenCvSdkObjectDetectionService> start({
    OpenCvObjectDetection nativeDetector = const OpenCvObjectDetection(),
    bool? isAndroid,
  }) async {
    if (!(isAndroid ?? Platform.isAndroid)) {
      throw UnsupportedError(
        'The OpenCV SDK object detector currently supports Android only.',
      );
    }

    await nativeDetector.initialize(
      modelAsset: HandGestureThresholds.opencvSdkModelAsset,
      metadataAsset: HandGestureThresholds.opencvSdkMetadataAsset,
      confidenceThreshold: HandGestureThresholds.opencvSdkConfidenceThreshold,
      iouThreshold: HandGestureThresholds.opencvSdkIouThreshold,
      maxResults: HandGestureThresholds.objectDetectionMaxResults,
      expectedClassCount: HandGestureThresholds.opencvSdkExpectedClassCount,
    );
    final capabilities = await nativeDetector.getCapabilities();
    if (kDebugMode) {
      debugPrint('OpenCV SDK object detector initialized: $capabilities');
    }
    return OpenCvSdkObjectDetectionService._(nativeDetector);
  }

  @override
  Future<List<AppObjectDetection>> performDetection(
    CameraImage image, {
    od.CameraFrameRotation? rotation,
    CameraLensDirection? lensDirection,
  }) async {
    final frameId = ++_nextFrameId;
    final response = await _nativeDetector.detect(
      frameArguments(
        image,
        frameId: frameId,
        rotation: rotation,
        lensDirection: lensDirection,
      ),
    );
    if (isClosed) return const [];

    final responseFrameId = _integer(response['frameId']);
    final expectedRotation = rotationDegrees(rotation);
    final expectedFacing = lensDirection?.name ?? 'unknown';
    if (responseFrameId != frameId ||
        responseFrameId! <= _lastAcceptedFrameId ||
        _integer(response['rotationDegrees']) != expectedRotation ||
        response['cameraFacing']?.toString() != expectedFacing ||
        response['coordinateSpace'] != 'upright_unmirrored') {
      if (kDebugMode) {
        debugPrint(
          'OpenCV SDK detector ignored mismatched frame response: '
          'requested=$frameId response=$responseFrameId.',
        );
      }
      return const [];
    }
    _lastAcceptedFrameId = responseFrameId;
    final detections = mapResponse(response);
    if (kDebugMode && (frameId == 1 || frameId % 10 == 0)) {
      final preprocessMs = _finiteDouble(response['preprocessMs']);
      final inferenceMs = _finiteDouble(response['inferenceMs']);
      final postprocessMs = _finiteDouble(response['postprocessMs']);
      debugPrint(
        'OpenCV SDK frame $frameId: '
        'preprocess=${preprocessMs?.toStringAsFixed(1) ?? 'unknown'}ms, '
        'inference=${inferenceMs?.toStringAsFixed(1) ?? 'unknown'}ms, '
        'postprocess=${postprocessMs?.toStringAsFixed(1) ?? 'unknown'}ms, '
        'detections=${detections.length}.',
      );
    }
    return detections;
  }

  @visibleForTesting
  static Map<String, Object?> frameArguments(
    CameraImage image, {
    required int frameId,
    required od.CameraFrameRotation? rotation,
    required CameraLensDirection? lensDirection,
  }) {
    return {
      'frameId': frameId,
      'width': image.width,
      'height': image.height,
      'format': image.format.group.name,
      'rotationDegrees': rotationDegrees(rotation),
      'cameraFacing': lensDirection?.name ?? 'unknown',
      'planes': [
        for (final plane in image.planes)
          {
            'bytes': plane.bytes,
            'bytesPerRow': plane.bytesPerRow,
            'bytesPerPixel': plane.bytesPerPixel ?? 1,
          },
      ],
    };
  }

  @visibleForTesting
  static int rotationDegrees(od.CameraFrameRotation? rotation) {
    return switch (rotation) {
      od.CameraFrameRotation.cw90 => 90,
      od.CameraFrameRotation.cw180 => 180,
      od.CameraFrameRotation.cw270 => 270,
      null => 0,
    };
  }

  /// Validates OpenCV output before it enters target-selection logic.
  @visibleForTesting
  static List<AppObjectDetection> mapResponse(Map<Object?, Object?> response) {
    final width = _finiteDouble(response['imageWidth']);
    final height = _finiteDouble(response['imageHeight']);
    final rawDetections = response['detections'];
    if (response['coordinateSpace'] != 'upright_unmirrored' ||
        width == null ||
        height == null ||
        width <= 0 ||
        height <= 0 ||
        rawDetections is! List) {
      return const [];
    }

    final imageSize = Size(width, height);
    final results = <AppObjectDetection>[];
    for (final rawDetection in rawDetections) {
      if (rawDetection is! Map) continue;
      final label = rawDetection['label']?.toString().trim() ?? '';
      final confidence = _finiteDouble(rawDetection['confidence']);
      final classIndex = _integer(rawDetection['classIndex']);
      final left = _finiteDouble(rawDetection['left']);
      final top = _finiteDouble(rawDetection['top']);
      final right = _finiteDouble(rawDetection['right']);
      final bottom = _finiteDouble(rawDetection['bottom']);
      if (label.isEmpty ||
          AppObjectDetection.isPersonLabel(label) ||
          confidence == null ||
          confidence < HandGestureThresholds.opencvSdkConfidenceThreshold ||
          confidence > 1 ||
          classIndex == null ||
          classIndex < 0 ||
          classIndex >= HandGestureThresholds.opencvSdkExpectedClassCount ||
          left == null ||
          top == null ||
          right == null ||
          bottom == null) {
        continue;
      }

      final normalized = Rect.fromLTRB(
        left.clamp(0.0, 1.0),
        top.clamp(0.0, 1.0),
        right.clamp(0.0, 1.0),
        bottom.clamp(0.0, 1.0),
      );
      if (normalized.isEmpty) continue;

      results.add(
        AppObjectDetection(
          boundingBox: Rect.fromLTRB(
            normalized.left * width,
            normalized.top * height,
            normalized.right * width,
            normalized.bottom * height,
          ),
          imageSize: imageSize,
          label: label,
          confidence: confidence,
          classIndex: classIndex,
          trackingId: _integer(rawDetection['trackingId']),
          source: AppObjectDetectionSource.opencvSdk,
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

  static double? _finiteDouble(Object? rawValue) {
    if (rawValue is! num) return null;
    final number = rawValue.toDouble();
    return number.isFinite ? number : null;
  }

  static int? _integer(Object? rawValue) {
    if (rawValue is! num || !rawValue.toDouble().isFinite) return null;
    return rawValue.toInt();
  }

  @override
  Future<void> disposeBackend() => _nativeDetector.dispose();
}
