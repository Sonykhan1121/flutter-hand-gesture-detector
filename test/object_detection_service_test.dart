import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:gesture_detector/hand_gesture_features/domain/models/app_object_detection.dart';
import 'package:gesture_detector/hand_gesture_features/domain/services/object_detection_service.dart';
import 'package:object_detection/object_detection.dart';

void main() {
  group('ObjectDetectionService platform backend', () {
    test('uses the configured YOLO backend on iOS', () {
      expect(
        ObjectDetectionService.usePackageBackendForPlatform(isIOS: true),
        isFalse,
      );
    });

    test('keeps Android on the configured YOLO backend', () {
      expect(
        ObjectDetectionService.usePackageBackendForPlatform(isIOS: false),
        isFalse,
      );
    });

    test('uses the lighter EfficientDet model only on iOS', () {
      expect(
        ObjectDetectionService.packageModelForPlatform(isIOS: true),
        ObjectDetectionModel.efficientDetLite0,
      );
      expect(
        ObjectDetectionService.packageModelForPlatform(isIOS: false),
        ObjectDetectionModel.efficientDetLite2,
      );
    });

    test('uses permissive, compact inference options only on iOS', () {
      final iosOptions = ObjectDetectionService.packageOptionsForPlatform(
        isIOS: true,
      );
      final otherOptions = ObjectDetectionService.packageOptionsForPlatform(
        isIOS: false,
      );

      expect(iosOptions.scoreThreshold, 0.35);
      expect(iosOptions.categoryDenylist, ['person']);
      expect(
        ObjectDetectionService.packageMaxDimensionForPlatform(isIOS: true),
        320,
      );
      expect(otherOptions.scoreThreshold, 0.60);
      expect(otherOptions.categoryDenylist, isEmpty);
      expect(
        ObjectDetectionService.packageMaxDimensionForPlatform(isIOS: false),
        640,
      );
    });
  });

  group('ObjectDetectionService YOLO mapping', () {
    test('maps normalized boxes and derives the real class index', () {
      final results = ObjectDetectionService.mapUltralyticsDetections(
        [
          _box(
            label: 'Bottle',
            confidence: 0.92,
            left: 0.10,
            top: 0.20,
            right: 0.40,
            bottom: 0.60,
          ),
        ],
        imageSize: const Size(640, 480),
        modelLabels: const ['person', 'bottle'],
      );

      expect(results, hasLength(1));
      expect(results.single.label, 'Bottle');
      expect(results.single.classIndex, 1);
      expect(results.single.trackingId, isNull);
      expect(results.single.source, AppObjectDetectionSource.ultralyticsYolo);
      expect(results.single.imageSize, const Size(640, 480));
      expect(results.single.boundingBox, const Rect.fromLTRB(64, 96, 256, 288));
    });

    test('filters person, blank, low-confidence, and malformed boxes', () {
      final results = ObjectDetectionService.mapUltralyticsDetections(
        [
          _box(label: 'Person', confidence: 0.99),
          _box(label: 'Chair', confidence: 0.40),
          _box(label: '', confidence: 0.99),
          _box(label: 'Broken', confidence: 0.99)..remove('x2_norm'),
          _box(label: 'Food', confidence: 0.85),
        ],
        imageSize: const Size(640, 480),
        modelLabels: const ['person', 'chair', 'food'],
      );

      expect(results.map((result) => result.label), ['Food']);
      expect(results.single.classIndex, 2);
    });

    test('sorts by confidence, clamps boxes, and retains five results', () {
      final boxes = [
        for (var index = 0; index < 7; index++)
          _box(
            label: 'class-$index',
            confidence: 0.60 + index * 0.05,
            left: index == 6 ? -0.2 : 0.1,
            right: index == 6 ? 1.2 : 0.9,
          ),
      ];

      final results = ObjectDetectionService.mapUltralyticsDetections(
        boxes,
        imageSize: const Size(100, 50),
        modelLabels: [for (var index = 0; index < 7; index++) 'class-$index'],
      );

      expect(results, hasLength(5));
      expect(results.first.label, 'class-6');
      expect(results.first.boundingBox.left, 0);
      expect(results.first.boundingBox.right, 100);
      expect(
        results.map((result) => result.confidence),
        orderedEquals([0.90, 0.85, 0.80, 0.75, 0.70]),
      );
    });

    test('parses ordered labels from model metadata', () {
      expect(
        ObjectDetectionService.labelsFromMetadata({
          'labels': [' person ', 'bottle', '', 3],
        }),
        ['person', 'bottle', '3'],
      );
      expect(
        ObjectDetectionService.labelsFromMetadata({'labels': 'bad'}),
        isEmpty,
      );
    });
  });
}

Map<String, dynamic> _box({
  required String label,
  required double confidence,
  double left = 0.1,
  double top = 0.1,
  double right = 0.5,
  double bottom = 0.5,
}) {
  return {
    'class': label,
    'confidence': confidence,
    'x1_norm': left,
    'y1_norm': top,
    'x2_norm': right,
    'y2_norm': bottom,
  };
}
