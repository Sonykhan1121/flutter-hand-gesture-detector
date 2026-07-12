import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gesture_detector/hand_gesture_features/domain/enums/follow_target_type.dart';
import 'package:gesture_detector/hand_gesture_features/domain/models/follow_target.dart';
import 'package:gesture_detector/hand_gesture_features/presentation/painters/follow_target_overlay_painter.dart';

void main() {
  test('repaints when confirmation changes the box to amber', () {
    final target = FollowTarget(
      type: FollowTargetType.object,
      boundingBox: const Rect.fromLTWH(0.3, 0.3, 0.2, 0.2),
      displayBox: const Rect.fromLTWH(0.3, 0.3, 0.2, 0.2),
      detectedAt: DateTime(2026),
      label: 'bottle',
      classIndex: 39,
    );
    final normal = FollowTargetOverlayPainter(target: target);
    final confirming = FollowTargetOverlayPainter(
      target: target,
      colorOverride: const Color(0xFFFFB020),
    );

    expect(confirming.shouldRepaint(normal), isTrue);
    expect(confirming.shouldRepaint(confirming), isFalse);
  });
}
