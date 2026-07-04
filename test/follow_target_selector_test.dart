import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gesture_detector/hand_gesture_features/domain/enums/follow_target_type.dart';
import 'package:gesture_detector/hand_gesture_features/domain/models/follow_target.dart';
import 'package:gesture_detector/hand_gesture_features/domain/services/follow_target_selector.dart';

void main() {
  group('FollowTargetSelector selectNearest', () {
    const selector = FollowTargetSelector();

    test('selects nearest object even when release point is outside boxes', () {
      final nearObject = _target(
        type: FollowTargetType.object,
        displayBox: const Rect.fromLTWH(0.70, 0.70, 0.10, 0.10),
        label: 'near',
      );
      final farObject = _target(
        type: FollowTargetType.object,
        displayBox: const Rect.fromLTWH(0.10, 0.10, 0.10, 0.10),
        label: 'far',
      );

      final selected = selector.selectNearest(
        releasePoint: const Offset(0.95, 0.95),
        faces: const [],
        objects: [farObject, nearObject],
      );

      expect(selected?.label, 'near');
    });

    test('selects nearest target across faces and objects', () {
      final face = _target(
        type: FollowTargetType.face,
        displayBox: const Rect.fromLTWH(0.70, 0.70, 0.10, 0.10),
        label: 'face',
      );
      final object = _target(
        type: FollowTargetType.object,
        displayBox: const Rect.fromLTWH(0.20, 0.20, 0.10, 0.10),
        label: 'object',
      );

      final selected = selector.selectNearest(
        releasePoint: const Offset(0.26, 0.26),
        faces: [face],
        objects: [object],
      );

      expect(selected?.label, 'object');
    });

    test('tie-breaks by smaller target area', () {
      final largeTarget = _target(
        type: FollowTargetType.object,
        displayBox: const Rect.fromLTWH(0.20, 0.20, 0.30, 0.30),
        label: 'large',
      );
      final smallTarget = _target(
        type: FollowTargetType.object,
        displayBox: const Rect.fromLTWH(0.30, 0.30, 0.10, 0.10),
        label: 'small',
      );

      final selected = selector.selectNearest(
        releasePoint: const Offset(0.35, 0.35),
        faces: const [],
        objects: [largeTarget, smallTarget],
      );

      expect(selected?.label, 'small');
    });

    test('keeps face before object on exact distance and area tie', () {
      final face = _target(
        type: FollowTargetType.face,
        displayBox: const Rect.fromLTWH(0.30, 0.30, 0.10, 0.10),
        label: 'face',
      );
      final object = _target(
        type: FollowTargetType.object,
        displayBox: const Rect.fromLTWH(0.30, 0.30, 0.10, 0.10),
        label: 'object',
      );

      final selected = selector.selectNearest(
        releasePoint: const Offset(0.35, 0.35),
        faces: [face],
        objects: [object],
      );

      expect(selected?.label, 'face');
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
