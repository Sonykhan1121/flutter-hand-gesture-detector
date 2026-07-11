import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gesture_detector/hand_gesture_features/domain/enums/follow_target_tracking_phase.dart';
import 'package:gesture_detector/hand_gesture_features/domain/enums/follow_target_type.dart';
import 'package:gesture_detector/hand_gesture_features/domain/models/follow_target.dart';
import 'package:gesture_detector/hand_gesture_features/domain/services/follow_target_tracking_progress.dart';

void main() {
  test('enters lost only after two unique missed detection cycles', () {
    final progress = FollowTargetTrackingProgress()..markVisible();

    expect(progress.recordVisibleMiss(), isFalse);
    expect(progress.phase, FollowTargetTrackingPhase.visible);
    expect(progress.recordVisibleMiss(), isTrue);
    expect(progress.phase, FollowTargetTrackingPhase.lost);
  });

  test('requires three continuous confirmations to resume', () {
    final progress = FollowTargetTrackingProgress()..markLost();
    final first = _target(const Rect.fromLTWH(0.4, 0.4, 0.1, 0.1));
    final second = _target(const Rect.fromLTWH(0.41, 0.4, 0.1, 0.1));
    final third = _target(const Rect.fromLTWH(0.42, 0.4, 0.1, 0.1));

    expect(
      progress.recordReacquisitionCandidate(first, isContinuous: false),
      isFalse,
    );
    expect(progress.confirmationCount, 1);
    expect(
      progress.recordReacquisitionCandidate(second, isContinuous: true),
      isFalse,
    );
    expect(progress.confirmationCount, 2);
    expect(
      progress.recordReacquisitionCandidate(third, isContinuous: true),
      isTrue,
    );
    expect(progress.confirmationCount, 3);
  });

  test('a discontinuous candidate restarts confirmation at one', () {
    final progress = FollowTargetTrackingProgress()..markLost();
    final candidate = _target(const Rect.fromLTWH(0.4, 0.4, 0.1, 0.1));

    progress.recordReacquisitionCandidate(candidate, isContinuous: false);
    progress.recordReacquisitionCandidate(candidate, isContinuous: true);
    progress.recordReacquisitionCandidate(candidate, isContinuous: false);

    expect(progress.confirmationCount, 1);
    expect(progress.phase, FollowTargetTrackingPhase.confirmingReacquisition);
  });
}

FollowTarget _target(Rect box) {
  return FollowTarget(
    type: FollowTargetType.object,
    boundingBox: box,
    displayBox: box,
    detectedAt: DateTime(2026),
    label: 'bottle',
    classIndex: 1,
  );
}
