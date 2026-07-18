import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gesture_detector/hand_gesture_features/domain/enums/follow_target_type.dart';
import 'package:gesture_detector/hand_gesture_features/domain/models/follow_target.dart';
import 'package:gesture_detector/hand_gesture_features/presentation/painters/object_detection_debug_painter.dart';

void main() {
  group('ObjectDetectionDebugPainter', () {
    testWidgets('renders face and object debug targets', (tester) async {
      final targets = [
        _target(
          type: FollowTargetType.face,
          displayBox: const Rect.fromLTWH(0.10, 0.10, 0.20, 0.20),
          label: 'Face',
        ),
        _target(
          type: FollowTargetType.object,
          displayBox: const Rect.fromLTWH(0.55, 0.45, 0.30, 0.30),
          label: 'Mobile stand',
        ),
      ];

      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: SizedBox(
            width: 320,
            height: 240,
            child: CustomPaint(
              painter: ObjectDetectionDebugPainter(targets: targets),
            ),
          ),
        ),
      );

      final customPaint = tester.widget<CustomPaint>(find.byType(CustomPaint));
      expect(customPaint.painter, isA<ObjectDetectionDebugPainter>());
    });

    test('repaints when painter inputs change', () {
      final targets = [
        _target(
          type: FollowTargetType.object,
          displayBox: const Rect.fromLTWH(0.20, 0.20, 0.20, 0.20),
          label: 'Object',
        ),
      ];

      final painter = ObjectDetectionDebugPainter(targets: targets);

      expect(
        painter.shouldRepaint(ObjectDetectionDebugPainter(targets: targets)),
        isFalse,
      );
      expect(
        painter.shouldRepaint(
          ObjectDetectionDebugPainter(targets: List.of(targets)),
        ),
        isTrue,
      );
      expect(
        painter.shouldRepaint(
          ObjectDetectionDebugPainter(
            targets: targets,
            labelPrefix: 'Release → ',
          ),
        ),
        isTrue,
      );
      expect(
        painter.shouldRepaint(
          ObjectDetectionDebugPainter(targets: targets, showLabels: false),
        ),
        isTrue,
      );
      expect(
        painter.shouldRepaint(
          ObjectDetectionDebugPainter(targets: targets, color: Colors.green),
        ),
        isTrue,
      );
      expect(
        painter.shouldRepaint(
          ObjectDetectionDebugPainter(targets: targets, previewQuarterTurns: 1),
        ),
        isTrue,
      );
    });
  });
}

FollowTarget _target({
  required FollowTargetType type,
  required Rect displayBox,
  required String label,
}) {
  return FollowTarget(
    type: type,
    boundingBox: displayBox,
    displayBox: displayBox,
    detectedAt: DateTime(2026),
    label: label,
  );
}
