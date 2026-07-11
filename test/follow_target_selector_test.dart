import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gesture_detector/hand_gesture_features/domain/enums/follow_target_type.dart';
import 'package:gesture_detector/hand_gesture_features/domain/models/appearance_signature.dart';
import 'package:gesture_detector/hand_gesture_features/domain/models/follow_target.dart';
import 'package:gesture_detector/hand_gesture_features/domain/models/follow_target_identity.dart';
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

    test('does not select a stale cached detection', () {
      final now = DateTime(2026, 1, 1, 0, 0, 2);
      final stale = _target(
        type: FollowTargetType.object,
        displayBox: const Rect.fromLTWH(0.30, 0.30, 0.10, 0.10),
        label: 'stale',
        detectedAt: now.subtract(const Duration(seconds: 2)),
      );

      final selected = selector.selectNearest(
        releasePoint: const Offset(0.35, 0.35),
        faces: const [],
        objects: [stale],
        detectedAfter: now.subtract(const Duration(milliseconds: 700)),
      );

      expect(selected, isNull);
    });
  });

  group('FollowTargetSelector immutable identity', () {
    const selector = FollowTargetSelector();

    test('visible tracking cannot transfer to a different label', () {
      final previous = _target(
        type: FollowTargetType.object,
        displayBox: const Rect.fromLTWH(0.40, 0.40, 0.10, 0.10),
        label: 'bottle',
      );
      final identity = FollowTargetIdentity.fromTarget(previous);

      final selected = selector.track(
        previous: previous,
        identity: identity,
        candidates: [
          _target(
            type: FollowTargetType.object,
            displayBox: const Rect.fromLTWH(0.40, 0.40, 0.10, 0.10),
            label: 'cup',
          ),
        ],
      );

      expect(selected, isNull);
      expect(identity.normalizedLabel, 'bottle');
    });

    test(
      'visible tracking accepts the exact class despite appearance change',
      () {
        final previous = _target(
          type: FollowTargetType.object,
          displayBox: const Rect.fromLTWH(0.40, 0.40, 0.10, 0.10),
          label: 'bottle',
        );
        final identity = FollowTargetIdentity.fromTarget(previous);
        final movedBottle = _target(
          type: FollowTargetType.object,
          displayBox: const Rect.fromLTWH(0.46, 0.42, 0.10, 0.10),
          label: 'bottle',
          appearanceSignature: AppearanceSignature(
            hsvHistogram: [0, 1, ...List<double>.filled(30, 0)],
            grayscaleHash: List<bool>.filled(64, false),
            aspectRatio: 1.5,
          ),
        );

        final selected = selector.track(
          previous: previous,
          identity: identity,
          candidates: [movedBottle],
        );

        expect(selected, movedBottle);
      },
    );

    test('visible tracking still rejects a different object class', () {
      final previous = _target(
        type: FollowTargetType.object,
        displayBox: const Rect.fromLTWH(0.40, 0.40, 0.10, 0.10),
        label: 'bottle',
        classIndex: 1,
      );
      final identity = FollowTargetIdentity.fromTarget(previous);

      final selected = selector.track(
        previous: previous,
        identity: identity,
        candidates: [
          _target(
            type: FollowTargetType.object,
            displayBox: const Rect.fromLTWH(0.42, 0.40, 0.10, 0.10),
            label: 'bottle',
            classIndex: 2,
          ),
        ],
      );

      expect(selected, isNull);
    });

    test('visible face tracking keeps its appearance guard', () {
      final previous = _target(
        type: FollowTargetType.face,
        displayBox: const Rect.fromLTWH(0.40, 0.40, 0.10, 0.10),
        label: 'Face',
      );
      final identity = FollowTargetIdentity.fromTarget(previous);

      final selected = selector.track(
        previous: previous,
        identity: identity,
        candidates: [
          _target(
            type: FollowTargetType.face,
            displayBox: const Rect.fromLTWH(0.42, 0.40, 0.10, 0.10),
            label: 'Face',
            appearanceSignature: AppearanceSignature(
              hsvHistogram: [0, 1, ...List<double>.filled(30, 0)],
              grayscaleHash: List<bool>.filled(64, false),
              aspectRatio: 1.5,
            ),
          ),
        ],
      );

      expect(selected, isNull);
    });
  });
}

FollowTarget _target({
  required FollowTargetType type,
  required Rect displayBox,
  required String label,
  int? trackingId,
  int? classIndex,
  AppearanceSignature? appearanceSignature,
  DateTime? detectedAt,
}) {
  return FollowTarget(
    type: type,
    boundingBox: displayBox,
    displayBox: displayBox,
    detectedAt: detectedAt ?? DateTime(2026),
    label: label,
    trackingId: trackingId,
    classIndex: classIndex ?? (type == FollowTargetType.object ? 1 : null),
    appearanceSignature: appearanceSignature ?? _signature(),
  );
}

AppearanceSignature _signature() {
  return AppearanceSignature(
    hsvHistogram: [1, ...List<double>.filled(31, 0)],
    grayscaleHash: List<bool>.filled(64, true),
    aspectRatio: 1,
  );
}
