import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:gesture_detector/hand_gesture_features/domain/models/app_object_detection.dart';
import 'package:gesture_detector/hand_gesture_features/domain/services/object_detection_service.dart';
import 'package:google_mlkit_object_detection/google_mlkit_object_detection.dart'
    as ml_object;

void main() {
  group('ObjectDetectionService ML Kit mapping', () {
    test('maps labels, class index, source, and tracking id', () {
      final results = ObjectDetectionService.mapGoogleMlKitDetections([
        ml_object.DetectedObject(
          boundingBox: const Rect.fromLTWH(10, 20, 30, 40),
          labels: [ml_object.Label(confidence: 0.92, index: 7, text: 'Bottle')],
          trackingId: 42,
        ),
      ], imageSize: const Size(640, 480));

      expect(results, hasLength(1));
      expect(results.single.label, 'Bottle');
      expect(results.single.classIndex, 7);
      expect(results.single.trackingId, 42);
      expect(results.single.source, AppObjectDetectionSource.googleMlKit);
      expect(results.single.imageSize, const Size(640, 480));
    });

    test('filters person and low-confidence ML Kit classifications', () {
      final results = ObjectDetectionService.mapGoogleMlKitDetections([
        _detected(label: 'Person', confidence: 0.99),
        _detected(label: 'Chair', confidence: 0.40),
        _detected(label: 'Food', confidence: 0.85),
      ], imageSize: const Size(640, 480));

      expect(results.map((result) => result.label), ['Food']);
    });

    test('keeps unclassified boxes as generic objects', () {
      final results = ObjectDetectionService.mapGoogleMlKitDetections([
        ml_object.DetectedObject(
          boundingBox: const Rect.fromLTWH(10, 20, 30, 40),
          labels: const [],
          trackingId: 5,
        ),
      ], imageSize: const Size(640, 480));

      expect(results.single.label, 'Object');
      expect(results.single.classIndex, -1);
      expect(results.single.confidence, 1);
    });
  });
}

ml_object.DetectedObject _detected({
  required String label,
  required double confidence,
}) {
  return ml_object.DetectedObject(
    boundingBox: const Rect.fromLTWH(10, 20, 30, 40),
    labels: [ml_object.Label(confidence: confidence, index: 1, text: label)],
    trackingId: 1,
  );
}
