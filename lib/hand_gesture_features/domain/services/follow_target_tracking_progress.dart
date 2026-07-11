import '../constants/hand_gesture_thresholds.dart';
import '../enums/follow_target_tracking_phase.dart';
import '../models/follow_target.dart';

/// Counts unique detector cycles for fail-closed loss and reacquisition.
class FollowTargetTrackingProgress {
  FollowTargetTrackingPhase phase = FollowTargetTrackingPhase.idle;
  int missedDetectionCount = 0;
  int confirmationCount = 0;
  FollowTarget? candidate;

  void markSelecting() {
    phase = FollowTargetTrackingPhase.selecting;
    missedDetectionCount = 0;
    resetReacquisition();
  }

  void markVisible() {
    phase = FollowTargetTrackingPhase.visible;
    missedDetectionCount = 0;
    resetReacquisition();
  }

  bool recordVisibleMiss() {
    missedDetectionCount++;
    if (missedDetectionCount <
        HandGestureThresholds.followTargetMissesBeforeLost) {
      return false;
    }
    markLost();
    return true;
  }

  void markLost() {
    phase = FollowTargetTrackingPhase.lost;
    resetReacquisition();
  }

  bool recordReacquisitionCandidate(
    FollowTarget next, {
    required bool isContinuous,
  }) {
    if (candidate == null || !isContinuous) {
      candidate = next;
      confirmationCount = 1;
    } else {
      candidate = next;
      confirmationCount++;
    }
    phase = FollowTargetTrackingPhase.confirmingReacquisition;
    return confirmationCount >=
        HandGestureThresholds.followTargetReacquisitionConfirmations;
  }

  void resetReacquisition() {
    candidate = null;
    confirmationCount = 0;
  }

  void reset() {
    phase = FollowTargetTrackingPhase.idle;
    missedDetectionCount = 0;
    resetReacquisition();
  }
}
