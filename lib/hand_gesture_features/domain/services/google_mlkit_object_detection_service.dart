import 'dart:io';
import 'dart:ui';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:google_mlkit_object_detection/google_mlkit_object_detection.dart'
    as ml_object;
import 'package:object_detection/object_detection.dart' as od;

import '../constants/hand_gesture_thresholds.dart';
import '../enums/object_detection_backend.dart';
import '../models/app_object_detection.dart';
import 'object_detection_service.dart';

/// Object detector implemented only with Google's native ML Kit package.
final class GoogleMlKitObjectDetectionService
    extends SingleFlightObjectDetectionService {
  GoogleMlKitObjectDetectionService._(this._detector);

  final ml_object.ObjectDetector _detector;
  var _processedFrames = 0;

  @override
  ObjectDetectionBackend get backend => ObjectDetectionBackend.googleMlKit;

  static ml_object.ObjectDetectorOptions liveOptions() {
    return ml_object.ObjectDetectorOptions(
      mode: ml_object.DetectionMode.stream,
      classifyObjects: true,
      multipleObjects: false,
    );
  }

  static Future<GoogleMlKitObjectDetectionService> start() async {
    return GoogleMlKitObjectDetectionService._(
      ml_object.ObjectDetector(options: liveOptions()),
    );
  }

  @override
  Future<List<AppObjectDetection>> performDetection(
    CameraImage image, {
    od.CameraFrameRotation? rotation,
  }) async {
    final inputImage = _inputImageFromCameraImage(image, rotation: rotation);
    if (inputImage == null) {
      debugPrint(
        'Google ML Kit object detector skipped unsupported camera frame: '
        '${image.format.group} ${image.width}x${image.height} '
        'planes=${image.planes.length}.',
      );
      return const [];
    }

    final objects = await _detector.processImage(inputImage);
    if (isClosed) return const [];

    _processedFrames++;
    if (objects.isEmpty) {
      if (_processedFrames == 1 || _processedFrames % 10 == 0) {
        debugPrint(
          'Google ML Kit object detector: 0 raw objects after '
          '$_processedFrames processed frames.',
        );
      }
    } else {
      for (final object in objects) {
        final labels = object.labels
            .map(
              (label) =>
                  '${label.text}(${label.confidence.toStringAsFixed(3)})',
            )
            .join(', ');
        debugPrint(
          'Google ML Kit raw object: box=${object.boundingBox} '
          'trackingId=${object.trackingId} '
          'labels=${labels.isEmpty ? '<none>' : labels}',
        );
      }
    }

    return mapDetections(
      objects,
      rawImageSize: Size(image.width.toDouble(), image.height.toDouble()),
      rotation: rotation,
      isIOS: Platform.isIOS,
    );
  }

  /// Converts native ML Kit results into the same app model as other services.
  static List<AppObjectDetection> mapDetections(
    Iterable<ml_object.DetectedObject> objects, {
    required Size rawImageSize,
    required od.CameraFrameRotation? rotation,
    required bool isIOS,
  }) {
    final imageSize = _uprightImageSize(
      rawImageSize,
      rotation: rotation,
      isIOS: isIOS,
    );
    if (imageSize.width <= 0 || imageSize.height <= 0) return const [];

    final results = <AppObjectDetection>[];
    for (final object in objects) {
      final bestLabel = object.labels.isEmpty
          ? null
          : object.labels.reduce(
              (best, next) => next.confidence > best.confidence ? next : best,
            );
      final classifiedLabel =
          bestLabel != null &&
              bestLabel.text.trim().isNotEmpty &&
              bestLabel.confidence >=
                  HandGestureThresholds.googleMlKitClassificationScoreThreshold
          ? bestLabel
          : null;
      final label = classifiedLabel != null
          ? classifiedLabel.text.trim()
          : 'Object';
      if (AppObjectDetection.isPersonLabel(label)) continue;

      final boundingBox = _uprightBoundingBox(
        object.boundingBox,
        imageSize: imageSize,
        rotation: rotation,
      );
      if (boundingBox.isEmpty) continue;
      results.add(
        AppObjectDetection(
          boundingBox: boundingBox,
          imageSize: imageSize,
          label: label,
          confidence: classifiedLabel?.confidence,
          classIndex: classifiedLabel?.index ?? -1,
          trackingId: object.trackingId,
          source: AppObjectDetectionSource.googleMlKit,
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

  static Size _uprightImageSize(
    Size rawImageSize, {
    required od.CameraFrameRotation? rotation,
    required bool isIOS,
  }) {
    // ML Kit ignores InputImageMetadata.rotation on iOS. The camera plugin's
    // BGRA buffer and returned boxes therefore retain their native dimensions.
    if (isIOS) return rawImageSize;
    return switch (rotation) {
      od.CameraFrameRotation.cw90 || od.CameraFrameRotation.cw270 => Size(
        rawImageSize.height,
        rawImageSize.width,
      ),
      od.CameraFrameRotation.cw180 || null => rawImageSize,
    };
  }

  static Rect _clampedRect(Rect rect, Size size) {
    return Rect.fromLTRB(
      rect.left.clamp(0.0, size.width),
      rect.top.clamp(0.0, size.height),
      rect.right.clamp(0.0, size.width),
      rect.bottom.clamp(0.0, size.height),
    );
  }

  static Rect _uprightBoundingBox(
    Rect rect, {
    required Size imageSize,
    required od.CameraFrameRotation? rotation,
  }) {
    // The ML Kit Flutter coordinate translator reverses X for a 270-degree
    // input. For 90 degrees the native box is already in the upright axes.
    // Mirroring for a front-camera preview still happens later in the common
    // display mapper, not in this detector-space conversion.
    final uprightRect = rotation == od.CameraFrameRotation.cw270
        ? Rect.fromLTRB(
            imageSize.width - rect.right,
            rect.top,
            imageSize.width - rect.left,
            rect.bottom,
          )
        : rect;
    return _clampedRect(uprightRect, imageSize);
  }

  static ml_object.InputImage? _inputImageFromCameraImage(
    CameraImage image, {
    required od.CameraFrameRotation? rotation,
  }) {
    final inputRotation = _inputRotation(rotation);
    if (Platform.isAndroid) {
      final bytes = _androidNv21Bytes(image);
      if (bytes == null) return null;
      return ml_object.InputImage.fromBytes(
        bytes: bytes,
        metadata: ml_object.InputImageMetadata(
          size: Size(image.width.toDouble(), image.height.toDouble()),
          rotation: inputRotation,
          format: ml_object.InputImageFormat.nv21,
          bytesPerRow: image.planes.first.bytesPerRow,
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
          rotation: inputRotation,
          format: format!,
          bytesPerRow: plane.bytesPerRow,
        ),
      );
    }

    return null;
  }

  static Uint8List? _androidNv21Bytes(CameraImage image) {
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
    final bytes = Uint8List(ySize + width * height ~/ 2);

    for (var row = 0; row < height; row++) {
      for (var column = 0; column < width; column++) {
        bytes[row * width + column] = _planeValue(yPlane, row, column);
      }
    }
    for (var row = 0; row < height ~/ 2; row++) {
      for (var column = 0; column < width ~/ 2; column++) {
        final outputIndex = ySize + row * width + column * 2;
        bytes[outputIndex] = _planeValue(vPlane, row, column);
        bytes[outputIndex + 1] = _planeValue(uPlane, row, column);
      }
    }
    return bytes;
  }

  static int _planeValue(Plane plane, int row, int column) {
    final pixelStride = plane.bytesPerPixel ?? 1;
    final index = row * plane.bytesPerRow + column * pixelStride;
    if (index < 0 || index >= plane.bytes.length) return 128;
    return plane.bytes[index];
  }

  static ml_object.InputImageRotation _inputRotation(
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

  @override
  Future<void> disposeBackend() => _detector.close();
}
