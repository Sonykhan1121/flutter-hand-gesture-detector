import 'dart:io';
import 'dart:typed_data';
import 'dart:ui';

import 'package:camera/camera.dart';
import 'package:google_mlkit_object_detection/google_mlkit_object_detection.dart'
    as ml_object;
import 'package:object_detection/object_detection.dart' as od;

import '../constants/hand_gesture_thresholds.dart';
import '../models/app_object_detection.dart';

/// Stable app-facing wrapper around either supported object detector backend.
class ObjectDetectionService {
  ObjectDetectionService._package(this._packageDetector)
    : _mlKitDetector = null;

  ObjectDetectionService._mlKit(this._mlKitDetector) : _packageDetector = null;

  final od.ObjectDetector? _packageDetector;
  final ml_object.ObjectDetector? _mlKitDetector;

  var _isBusy = false;
  var _isClosed = false;

  bool get isBusy => _isBusy;

  static const _options = od.ObjectDetectorOptions(
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

    return ObjectDetectionService._mlKit(
      ml_object.ObjectDetector(
        options: ml_object.ObjectDetectorOptions(
          mode: ml_object.DetectionMode.stream,
          classifyObjects: true,
          multipleObjects: true,
        ),
      ),
    );
  }

  Future<List<AppObjectDetection>> detect(
    CameraImage image, {
    od.CameraFrameRotation? rotation,
  }) async {
    if (_isClosed) return const [];
    if (_isBusy) throw StateError('Object detector is busy.');

    _isBusy = true;
    try {
      final packageDetector = _packageDetector;
      if (packageDetector != null) {
        return _detectWithPackage(packageDetector, image, rotation);
      }
      final mlKitDetector = _mlKitDetector;
      if (mlKitDetector != null) {
        return _detectWithMlKit(mlKitDetector, image, rotation);
      }
      return const [];
    } finally {
      _isBusy = false;
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
      options: _options,
    );

    return [
      for (final object in objects)
        if (!AppObjectDetection.isPersonLabel(object.categoryName))
          AppObjectDetection.fromDetectedObject(object),
    ];
  }

  Future<List<AppObjectDetection>> _detectWithMlKit(
    ml_object.ObjectDetector detector,
    CameraImage image,
    od.CameraFrameRotation? rotation,
  ) async {
    final inputImage = _mlKitInputImage(image, rotation);
    if (inputImage == null) return const [];

    final detectedObjects = await detector.processImage(inputImage);
    return mapGoogleMlKitDetections(
      detectedObjects,
      imageSize: Size(image.width.toDouble(), image.height.toDouble()),
    );
  }

  /// Converts native ML Kit results into the same model as the package backend.
  static List<AppObjectDetection> mapGoogleMlKitDetections(
    List<ml_object.DetectedObject> detectedObjects, {
    required Size imageSize,
  }) {
    final results = <AppObjectDetection>[];
    for (final object in detectedObjects) {
      ml_object.Label? bestLabel;
      for (final label in object.labels) {
        if (bestLabel == null || label.confidence > bestLabel.confidence) {
          bestLabel = label;
        }
      }

      final label = bestLabel?.text.trim().isNotEmpty == true
          ? bestLabel!.text
          : 'Object';
      if (AppObjectDetection.isPersonLabel(label)) continue;
      if (bestLabel != null &&
          bestLabel.confidence <
              HandGestureThresholds.objectDetectionScoreThreshold) {
        continue;
      }

      results.add(
        AppObjectDetection(
          boundingBox: object.boundingBox,
          imageSize: imageSize,
          label: label,
          confidence: bestLabel?.confidence ?? 1,
          classIndex: bestLabel?.index ?? -1,
          trackingId: object.trackingId,
          source: AppObjectDetectionSource.googleMlKit,
        ),
      );
      if (results.length >= HandGestureThresholds.objectDetectionMaxResults) {
        break;
      }
    }
    return results;
  }

  ml_object.InputImage? _mlKitInputImage(
    CameraImage image,
    od.CameraFrameRotation? rotation,
  ) {
    if (Platform.isAndroid) {
      final bytes = _androidNv21Bytes(image);
      if (bytes == null) return null;
      return ml_object.InputImage.fromBytes(
        bytes: bytes,
        metadata: ml_object.InputImageMetadata(
          size: Size(image.width.toDouble(), image.height.toDouble()),
          rotation: _mlKitRotation(rotation),
          format: ml_object.InputImageFormat.nv21,
          bytesPerRow: image.width,
        ),
      );
    }

    if (Platform.isIOS) {
      final format = ml_object.InputImageFormatValue.fromRawValue(
        image.format.raw,
      );
      if (format != ml_object.InputImageFormat.bgra8888 ||
          image.planes.length != 1) {
        return null;
      }
      final plane = image.planes.first;
      return ml_object.InputImage.fromBytes(
        bytes: plane.bytes,
        metadata: ml_object.InputImageMetadata(
          size: Size(image.width.toDouble(), image.height.toDouble()),
          rotation: _mlKitRotation(rotation),
          format: format!,
          bytesPerRow: plane.bytesPerRow,
        ),
      );
    }
    return null;
  }

  ml_object.InputImageRotation _mlKitRotation(
    od.CameraFrameRotation? rotation,
  ) {
    return switch (rotation) {
      od.CameraFrameRotation.cw90 => ml_object.InputImageRotation.rotation90deg,
      od.CameraFrameRotation.cw180 =>
        ml_object.InputImageRotation.rotation180deg,
      od.CameraFrameRotation.cw270 =>
        ml_object.InputImageRotation.rotation270deg,
      null => ml_object.InputImageRotation.rotation0deg,
    };
  }

  Uint8List? _androidNv21Bytes(CameraImage image) {
    final format = ml_object.InputImageFormatValue.fromRawValue(
      image.format.raw,
    );
    if (format == ml_object.InputImageFormat.nv21 && image.planes.length == 1) {
      return image.planes.first.bytes;
    }
    if (image.planes.length < 3 || image.width.isOdd || image.height.isOdd) {
      return null;
    }

    final width = image.width;
    final height = image.height;
    final yPlane = image.planes[0];
    final uPlane = image.planes[1];
    final vPlane = image.planes[2];
    final ySize = width * height;
    final out = Uint8List(ySize + width * height ~/ 2);

    for (var row = 0; row < height; row++) {
      for (var col = 0; col < width; col++) {
        out[row * width + col] = _planeValue(yPlane, row, col);
      }
    }
    for (var row = 0; row < height ~/ 2; row++) {
      for (var col = 0; col < width ~/ 2; col++) {
        final index = ySize + row * width + col * 2;
        out[index] = _planeValue(vPlane, row, col);
        out[index + 1] = _planeValue(uPlane, row, col);
      }
    }
    return out;
  }

  int _planeValue(Plane plane, int row, int col) {
    final index = row * plane.bytesPerRow + col * (plane.bytesPerPixel ?? 1);
    if (index < 0 || index >= plane.bytes.length) return 128;
    return plane.bytes[index];
  }

  Future<void> close() async {
    if (_isClosed) return;
    _isClosed = true;
    await _packageDetector?.dispose();
    await _mlKitDetector?.close();
  }
}
