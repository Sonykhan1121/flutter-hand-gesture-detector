import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gesture_detector/hand_gesture_features/domain/enums/follow_target_type.dart';
import 'package:gesture_detector/hand_gesture_features/domain/models/follow_target.dart';
import 'package:gesture_detector/hand_gesture_features/domain/services/follow_target_pointing_dwell_controller.dart';

void main() {
  group('FollowTargetPointingDwellController', () {
    test('requires 500ms and two genuinely fresh detection cycles', () {
      final controller = FollowTargetPointingDwellController();
      final start = DateTime(2026);
      final target = _target(detectedAt: start, trackingId: 7);

      controller.observe(
        candidate: target,
        detectionCycleAt: start,
        now: start,
      );
      final secondCycle = controller.observe(
        candidate: _target(
          detectedAt: start.add(const Duration(milliseconds: 200)),
          trackingId: 7,
          box: const Rect.fromLTWH(0.21, 0.20, 0.20, 0.20),
        ),
        detectionCycleAt: start.add(const Duration(milliseconds: 200)),
        now: start.add(const Duration(milliseconds: 499)),
      );
      expect(secondCycle.freshDetectionCycles, 2);
      expect(secondCycle.isComplete, isFalse);

      final exactBoundary = controller.observe(
        candidate: secondCycle.candidate,
        detectionCycleAt: start.add(const Duration(milliseconds: 200)),
        now: start.add(const Duration(milliseconds: 500)),
      );
      expect(exactBoundary.isComplete, isTrue);
      expect(controller.isFrozen, isTrue);
      expect(
        controller.confirmationDeadline,
        start.add(const Duration(milliseconds: 2500)),
      );
    });

    test('does not complete from one reused detector cycle', () {
      final controller = FollowTargetPointingDwellController();
      final start = DateTime(2026);
      final target = _target(detectedAt: start, trackingId: 7);
      controller.observe(
        candidate: target,
        detectionCycleAt: start,
        now: start,
      );

      final reused = controller.observe(
        candidate: target,
        detectionCycleAt: start,
        now: start.add(const Duration(seconds: 1)),
      );

      expect(reused.progress, 1);
      expect(reused.freshDetectionCycles, 1);
      expect(reused.isComplete, isFalse);
      expect(controller.isFrozen, isFalse);
    });

    test('different candidate restarts dwell instead of transferring it', () {
      final controller = FollowTargetPointingDwellController();
      final start = DateTime(2026);
      controller.observe(
        candidate: _target(detectedAt: start, trackingId: 7),
        detectionCycleAt: start,
        now: start,
      );

      final changed = controller.observe(
        candidate: _target(
          detectedAt: start.add(const Duration(milliseconds: 400)),
          trackingId: 8,
          box: const Rect.fromLTWH(0.60, 0.60, 0.20, 0.20),
        ),
        detectionCycleAt: start.add(const Duration(milliseconds: 400)),
        now: start.add(const Duration(milliseconds: 400)),
      );

      expect(changed.restarted, isTrue);
      expect(
        changed.resetReason,
        FollowTargetPointingResetReason.candidateChanged,
      );
      expect(changed.progress, 0);
      expect(changed.freshDetectionCycles, 1);
    });

    test('confirmation remains valid at deadline and expires later', () {
      final controller = FollowTargetPointingDwellController();
      final start = DateTime(2026);
      controller.observe(
        candidate: _target(detectedAt: start, trackingId: 7),
        detectionCycleAt: start,
        now: start,
      );
      controller.observe(
        candidate: _target(
          detectedAt: start.add(const Duration(milliseconds: 250)),
          trackingId: 7,
        ),
        detectionCycleAt: start.add(const Duration(milliseconds: 250)),
        now: start.add(const Duration(milliseconds: 500)),
      );
      final deadline = controller.confirmationDeadline!;

      expect(controller.confirmationExpired(deadline), isFalse);
      expect(
        controller.confirmationExpired(
          deadline.add(const Duration(milliseconds: 1)),
        ),
        isTrue,
      );
    });

    test('reset clears candidate, progress, and frozen identity', () {
      final controller = FollowTargetPointingDwellController();
      final start = DateTime(2026);
      controller.observe(
        candidate: _target(detectedAt: start, trackingId: 7),
        detectionCycleAt: start,
        now: start,
      );

      controller.reset(FollowTargetPointingResetReason.handMissing);

      expect(controller.candidate, isNull);
      expect(controller.frozenTarget, isNull);
      expect(controller.progress(start), 0);
      expect(
        controller.lastResetReason,
        FollowTargetPointingResetReason.handMissing,
      );
    });
  });
}

FollowTarget _target({
  required DateTime detectedAt,
  required int trackingId,
  Rect box = const Rect.fromLTWH(0.20, 0.20, 0.20, 0.20),
}) {
  return FollowTarget(
    type: FollowTargetType.object,
    boundingBox: box,
    displayBox: box,
    detectedAt: detectedAt,
    trackingId: trackingId,
    label: 'cup',
    classIndex: 1,
  );
}
