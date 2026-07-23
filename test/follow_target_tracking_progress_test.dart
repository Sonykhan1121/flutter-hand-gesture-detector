import 'package:flutter_test/flutter_test.dart';
import 'package:gesture_detector/hand_gesture_features/domain/enums/follow_target_tracking_phase.dart';
import 'package:gesture_detector/hand_gesture_features/domain/services/follow_target_tracking_progress.dart';

void main() {
  test('clears a visible target after two fresh detector misses', () {
    final progress = FollowTargetTrackingProgress()..markVisible();

    expect(progress.recordVisibleMiss(), isFalse);
    expect(progress.phase, FollowTargetTrackingPhase.visible);
    expect(progress.recordVisibleMiss(), isTrue);
    expect(progress.missedDetectionCount, 2);
  });

  test('a successful match resets the detector miss count', () {
    final progress = FollowTargetTrackingProgress()..markVisible();

    progress.recordVisibleMiss();
    progress.markVisible();

    expect(progress.recordVisibleMiss(), isFalse);
    expect(progress.missedDetectionCount, 1);
  });

  test('reset forgets the previous target progress completely', () {
    final progress = FollowTargetTrackingProgress()..markVisible();
    progress.recordVisibleMiss();

    progress.reset();

    expect(progress.phase, FollowTargetTrackingPhase.idle);
    expect(progress.missedDetectionCount, 0);
  });

  test('post-release confirmation has a distinct tracking phase', () {
    final progress = FollowTargetTrackingProgress()..markConfirmingSelection();

    expect(progress.phase, FollowTargetTrackingPhase.confirmingSelection);
    expect(progress.missedDetectionCount, 0);

    progress.markVisible();
    expect(progress.phase, FollowTargetTrackingPhase.visible);
  });

  test('temporarily lost is distinct and clears the miss count', () {
    final progress = FollowTargetTrackingProgress()..markVisible();
    progress.recordVisibleMiss();

    progress.markTemporarilyLost();

    expect(progress.phase, FollowTargetTrackingPhase.temporarilyLost);
    expect(progress.missedDetectionCount, 0);
  });
}
