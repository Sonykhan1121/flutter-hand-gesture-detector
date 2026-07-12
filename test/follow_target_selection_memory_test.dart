import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gesture_detector/hand_gesture_features/domain/enums/follow_target_type.dart';
import 'package:gesture_detector/hand_gesture_features/domain/models/follow_target.dart';
import 'package:gesture_detector/hand_gesture_features/domain/models/follow_target_selection_memory.dart';

void main() {
  final firstCycle = DateTime(2026, 1, 1, 12);
  const handPoint = Offset(0.5, 0.5);

  test('requires two distinct detector cycles before release', () {
    final first = FollowTargetSelectionMemory.firstObservation(
      candidate: _target(firstCycle),
      observedAt: firstCycle,
      handPoint: handPoint,
    );
    final reused = first.observeFreshCycle(
      candidate: _target(firstCycle),
      observedAt: firstCycle.add(const Duration(milliseconds: 100)),
      handPoint: handPoint,
    );
    final confirmed = reused.observeFreshCycle(
      candidate: _target(firstCycle.add(const Duration(milliseconds: 350))),
      observedAt: firstCycle.add(const Duration(milliseconds: 350)),
      handPoint: handPoint,
    );

    expect(first.isReleasable, isFalse);
    expect(reused.consecutiveConfirmationCount, 1);
    expect(reused.isReleasable, isFalse);
    expect(confirmed.consecutiveConfirmationCount, 2);
    expect(confirmed.isReleasable, isTrue);
  });

  test('cached observations do not extend the two-second lifetime', () {
    final memory = FollowTargetSelectionMemory.firstObservation(
      candidate: _target(firstCycle),
      observedAt: firstCycle,
      handPoint: handPoint,
    );
    final reused = memory.observeFreshCycle(
      candidate: _target(firstCycle),
      observedAt: firstCycle.add(const Duration(seconds: 1)),
      handPoint: handPoint,
    );

    expect(
      reused.isValid(
        now: firstCycle.add(const Duration(milliseconds: 2001)),
        handPoint: handPoint,
      ),
      isFalse,
    );
  });

  test(
    'invalidates when the hand moves more than 0.15 normalized distance',
    () {
      final memory = FollowTargetSelectionMemory.firstObservation(
        candidate: _target(firstCycle),
        observedAt: firstCycle,
        handPoint: handPoint,
      );

      expect(
        memory.isValid(
          now: firstCycle.add(const Duration(milliseconds: 100)),
          handPoint: const Offset(0.64, 0.5),
        ),
        isTrue,
      );
      expect(
        memory.isValid(
          now: firstCycle.add(const Duration(milliseconds: 100)),
          handPoint: const Offset(0.66, 0.5),
        ),
        isFalse,
      );
    },
  );
}

FollowTarget _target(DateTime detectedAt) {
  const box = Rect.fromLTWH(0.4, 0.4, 0.2, 0.2);
  return FollowTarget(
    type: FollowTargetType.object,
    boundingBox: box,
    displayBox: box,
    detectedAt: detectedAt,
    label: 'bottle',
    classIndex: 39,
  );
}
