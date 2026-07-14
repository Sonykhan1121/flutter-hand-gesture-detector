import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gesture_detector/hand_gesture_features/domain/enums/follow_target_type.dart';
import 'package:gesture_detector/hand_gesture_features/domain/enums/object_detection_backend.dart';
import 'package:gesture_detector/hand_gesture_features/domain/models/follow_target.dart';
import 'package:gesture_detector/hand_gesture_features/presentation/painters/google_mlkit_object_debug_painter.dart';
import 'package:gesture_detector/hand_gesture_features/presentation/painters/object_detection_debug_painter_factory.dart';
import 'package:gesture_detector/hand_gesture_features/presentation/painters/object_detection_package_debug_painter.dart';
import 'package:gesture_detector/hand_gesture_features/presentation/painters/ultralytics_yolo_debug_painter.dart';

void main() {
  final targets = [
    FollowTarget(
      type: FollowTargetType.object,
      boundingBox: const Rect.fromLTWH(10, 10, 30, 30),
      displayBox: const Rect.fromLTWH(0.1, 0.1, 0.3, 0.3),
      detectedAt: DateTime(2026),
      label: 'Object',
    ),
  ];

  test('routes every backend to its own debug painter', () {
    expect(
      ObjectDetectionDebugPainterFactory.create(
        backend: ObjectDetectionBackend.objectDetectionPackage,
        targets: targets,
      ),
      isA<ObjectDetectionPackageDebugPainter>(),
    );
    expect(
      ObjectDetectionDebugPainterFactory.create(
        backend: ObjectDetectionBackend.ultralyticsYolo,
        targets: targets,
      ),
      isA<UltralyticsYoloDebugPainter>(),
    );
    expect(
      ObjectDetectionDebugPainterFactory.create(
        backend: ObjectDetectionBackend.googleMlKit,
        targets: targets,
      ),
      isA<GoogleMlKitObjectDebugPainter>(),
    );
  });

  test('keeps the same painter inputs for every backend', () {
    for (final backend in ObjectDetectionBackend.values) {
      final painter = ObjectDetectionDebugPainterFactory.create(
        backend: backend,
        targets: targets,
        showLabels: false,
        color: Colors.purple,
        labelPrefix: 'Debug: ',
        previewQuarterTurns: 1,
      );

      expect(painter.targets, same(targets));
      expect(painter.showLabels, isFalse);
      expect(painter.color, Colors.purple);
      expect(painter.labelPrefix, 'Debug: ');
      expect(painter.previewQuarterTurns, 1);
    }
  });
}
