import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gesture_detector/hand_gesture_features/domain/enums/follow_target_type.dart';
import 'package:gesture_detector/hand_gesture_features/domain/enums/object_detection_backend.dart';
import 'package:gesture_detector/hand_gesture_features/domain/models/follow_target.dart';
import 'package:gesture_detector/hand_gesture_features/presentation/painters/object_detection_debug_painter.dart';
import 'package:gesture_detector/hand_gesture_features/presentation/painters/object_detection_debug_painter_factory.dart';

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

  test('uses one shared painter for every backend', () {
    for (final backend in ObjectDetectionBackend.values) {
      expect(
        ObjectDetectionDebugPainterFactory.create(
          backend: backend,
          targets: targets,
        ),
        isA<ObjectDetectionDebugPainter>(),
      );
    }
  });

  test('preserves each backend default color', () {
    const expectedColors = {
      ObjectDetectionBackend.objectDetectionPackage: Color(0xFFFFA726),
      ObjectDetectionBackend.ultralyticsYolo: Color(0xFF00FB46),
      ObjectDetectionBackend.googleMlKit: Color(0xFF29B6F6),
      ObjectDetectionBackend.nativeMethodChannel: Color(0xFFFFA726),
      ObjectDetectionBackend.opencvSdk: Color(0xFF00A3A3),
    };

    for (final MapEntry(key: backend, value: color) in expectedColors.entries) {
      final painter = ObjectDetectionDebugPainterFactory.create(
        backend: backend,
        targets: targets,
      );
      expect(painter.color, color, reason: backend.name);
    }
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
