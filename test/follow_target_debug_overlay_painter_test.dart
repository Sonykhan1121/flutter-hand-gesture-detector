import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gesture_detector/hand_gesture_features/domain/enums/follow_target_type.dart';
import 'package:gesture_detector/hand_gesture_features/domain/models/follow_target.dart';
import 'package:gesture_detector/hand_gesture_features/presentation/painters/follow_target_debug_overlay_painter.dart';

void main() {
  group('FollowTargetDebugOverlayPainter', () {
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
              painter: FollowTargetDebugOverlayPainter(targets: targets),
            ),
          ),
        ),
      );

      final customPaint = tester.widget<CustomPaint>(find.byType(CustomPaint));
      expect(customPaint.painter, isA<FollowTargetDebugOverlayPainter>());
    });

    test('repaints when target list changes', () {
      final targets = [
        _target(
          type: FollowTargetType.object,
          displayBox: const Rect.fromLTWH(0.20, 0.20, 0.20, 0.20),
          label: 'Object',
        ),
      ];

      final painter = FollowTargetDebugOverlayPainter(targets: targets);

      expect(
        painter.shouldRepaint(
          FollowTargetDebugOverlayPainter(targets: targets),
        ),
        isFalse,
      );
      expect(
        painter.shouldRepaint(
          FollowTargetDebugOverlayPainter(targets: List.of(targets)),
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
