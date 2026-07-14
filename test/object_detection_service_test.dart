import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:google_mlkit_object_detection/google_mlkit_object_detection.dart'
    as ml_object;
import 'package:gesture_detector/hand_gesture_features/domain/enums/object_detection_backend.dart';
import 'package:gesture_detector/hand_gesture_features/domain/models/app_object_detection.dart';
import 'package:gesture_detector/hand_gesture_features/domain/services/google_mlkit_object_detection_service.dart';
import 'package:gesture_detector/hand_gesture_features/domain/services/object_detection_package_service.dart';
import 'package:gesture_detector/hand_gesture_features/domain/services/object_detection_service_factory.dart';
import 'package:gesture_detector/hand_gesture_features/domain/services/ultralytics_yolo_object_detection_service.dart';
import 'package:object_detection/object_detection.dart';

void main() {
  group('ObjectDetectionService platform backend', () {
    test('exposes all three selectable backends', () {
      expect(ObjectDetectionBackend.values, [
        ObjectDetectionBackend.objectDetectionPackage,
        ObjectDetectionBackend.ultralyticsYolo,
        ObjectDetectionBackend.googleMlKit,
      ]);
    });

    test('uses the lighter EfficientDet model only on iOS', () {
      expect(
        ObjectDetectionPackageService.packageModelForPlatform(isIOS: true),
        ObjectDetectionModel.efficientDetLite0,
      );
      expect(
        ObjectDetectionPackageService.packageModelForPlatform(isIOS: false),
        ObjectDetectionModel.efficientDetLite2,
      );
    });

    test('uses permissive, compact inference options only on iOS', () {
      final iosOptions =
          ObjectDetectionPackageService.packageOptionsForPlatform(isIOS: true);
      final otherOptions =
          ObjectDetectionPackageService.packageOptionsForPlatform(isIOS: false);

      expect(iosOptions.scoreThreshold, 0.35);
      expect(iosOptions.categoryDenylist, ['person']);
      expect(
        ObjectDetectionPackageService.packageMaxDimensionForPlatform(
          isIOS: true,
        ),
        320,
      );
      expect(otherOptions.scoreThreshold, 0.60);
      expect(otherOptions.categoryDenylist, isEmpty);
      expect(
        ObjectDetectionPackageService.packageMaxDimensionForPlatform(
          isIOS: false,
        ),
        640,
      );
    });

    test(
      'uses prominent-object live options and a faster cadence for ML Kit',
      () {
        final options = GoogleMlKitObjectDetectionService.liveOptions();

        expect(options.mode, ml_object.DetectionMode.stream);
        expect(options.classifyObjects, isTrue);
        expect(options.multipleObjects, isFalse);
        expect(
          ObjectDetectionServiceFactory.requestMinIntervalFor(
            backend: ObjectDetectionBackend.googleMlKit,
            isIOS: false,
          ),
          const Duration(milliseconds: 100),
        );
        expect(
          ObjectDetectionServiceFactory.requestMinIntervalFor(
            backend: ObjectDetectionBackend.ultralyticsYolo,
            isIOS: false,
          ),
          const Duration(milliseconds: 350),
        );
      },
    );
  });

  group('ObjectDetectionService YOLO mapping', () {
    test('maps normalized boxes and derives the real class index', () {
      final results = UltralyticsYoloObjectDetectionService.mapDetections(
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
      final results = UltralyticsYoloObjectDetectionService.mapDetections(
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

      final results = UltralyticsYoloObjectDetectionService.mapDetections(
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
        UltralyticsYoloObjectDetectionService.labelsFromMetadata({
          'labels': [' person ', 'bottle', '', 3],
        }),
        ['person', 'bottle', '3'],
      );
      expect(
        UltralyticsYoloObjectDetectionService.labelsFromMetadata({
          'labels': 'bad',
        }),
        isEmpty,
      );
    });
  });

  group('ObjectDetectionService Google ML Kit mapping', () {
    test('maps labels, tracking IDs, and Android quarter-turn coordinates', () {
      final results = GoogleMlKitObjectDetectionService.mapDetections(
        [
          ml_object.DetectedObject(
            boundingBox: const Rect.fromLTRB(40, 60, 160, 240),
            labels: [
              ml_object.Label(confidence: 0.91, index: 2, text: 'Home good'),
            ],
            trackingId: 7,
          ),
        ],
        rawImageSize: const Size(640, 480),
        rotation: CameraFrameRotation.cw90,
        isIOS: false,
      );

      expect(results, hasLength(1));
      expect(results.single.imageSize, const Size(480, 640));
      expect(results.single.boundingBox, const Rect.fromLTRB(40, 60, 160, 240));
      expect(results.single.label, 'Home good');
      expect(results.single.classIndex, 2);
      expect(results.single.trackingId, 7);
      expect(results.single.source, AppObjectDetectionSource.googleMlKit);
    });

    test('uses a generic label when the base detector returns no labels', () {
      final results = GoogleMlKitObjectDetectionService.mapDetections(
        [
          ml_object.DetectedObject(
            boundingBox: const Rect.fromLTRB(10, 20, 80, 100),
            labels: const [],
            trackingId: null,
          ),
        ],
        rawImageSize: const Size(200, 100),
        rotation: null,
        isIOS: true,
      );

      expect(results.single.label, 'Object');
      expect(results.single.confidence, isNull);
      expect(results.single.classIndex, -1);
    });

    test(
      'keeps boxes with uncertain labels and still filters person labels',
      () {
        final results = GoogleMlKitObjectDetectionService.mapDetections(
          [
            _mlKitObject(label: 'Food', confidence: 0.40),
            _mlKitObject(label: 'Person', confidence: 0.99),
            _mlKitObject(label: 'Plant', confidence: 0.85),
          ],
          rawImageSize: const Size(200, 100),
          rotation: null,
          isIOS: false,
        );

        expect(results.map((result) => result.label), ['Plant', 'Object']);
        expect(results.last.confidence, isNull);
        expect(results.last.classIndex, -1);
      },
    );

    test('maps Android boxes for every camera rotation', () {
      final object = ml_object.DetectedObject(
        boundingBox: const Rect.fromLTRB(40, 60, 160, 240),
        labels: [
          ml_object.Label(confidence: 0.91, index: 2, text: 'Home good'),
        ],
        trackingId: 7,
      );

      for (final testCase in [
        (
          rotation: null,
          imageSize: const Size(640, 480),
          box: const Rect.fromLTRB(40, 60, 160, 240),
        ),
        (
          rotation: CameraFrameRotation.cw90,
          imageSize: const Size(480, 640),
          box: const Rect.fromLTRB(40, 60, 160, 240),
        ),
        (
          rotation: CameraFrameRotation.cw180,
          imageSize: const Size(640, 480),
          box: const Rect.fromLTRB(40, 60, 160, 240),
        ),
        (
          rotation: CameraFrameRotation.cw270,
          imageSize: const Size(480, 640),
          box: const Rect.fromLTRB(320, 60, 440, 240),
        ),
      ]) {
        final results = GoogleMlKitObjectDetectionService.mapDetections(
          [object],
          rawImageSize: const Size(640, 480),
          rotation: testCase.rotation,
          isIOS: false,
        );

        expect(results.single.imageSize, testCase.imageSize);
        expect(results.single.boundingBox, testCase.box);
      }
    });

    test('maps iOS boxes for every camera rotation', () {
      final object = ml_object.DetectedObject(
        boundingBox: const Rect.fromLTRB(20, 10, 80, 60),
        labels: [
          ml_object.Label(confidence: 0.91, index: 2, text: 'Home good'),
        ],
        trackingId: 7,
      );

      for (final testCase in [
        (rotation: null, box: const Rect.fromLTRB(20, 10, 80, 60)),
        (
          rotation: CameraFrameRotation.cw90,
          box: const Rect.fromLTRB(20, 10, 80, 60),
        ),
        (
          rotation: CameraFrameRotation.cw180,
          box: const Rect.fromLTRB(20, 10, 80, 60),
        ),
        (
          rotation: CameraFrameRotation.cw270,
          box: const Rect.fromLTRB(120, 10, 180, 60),
        ),
      ]) {
        final results = GoogleMlKitObjectDetectionService.mapDetections(
          [object],
          rawImageSize: const Size(200, 100),
          rotation: testCase.rotation,
          isIOS: true,
        );

        expect(results.single.imageSize, const Size(200, 100));
        expect(results.single.boundingBox, testCase.box);
      }
    });
  });
}

ml_object.DetectedObject _mlKitObject({
  required String label,
  required double confidence,
}) {
  return ml_object.DetectedObject(
    boundingBox: const Rect.fromLTRB(10, 10, 50, 50),
    labels: [ml_object.Label(confidence: confidence, index: 0, text: label)],
    trackingId: null,
  );
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
