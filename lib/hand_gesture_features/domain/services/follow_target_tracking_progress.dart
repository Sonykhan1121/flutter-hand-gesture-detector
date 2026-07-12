import '../constants/hand_gesture_thresholds.dart';
import '../enums/follow_target_tracking_phase.dart';

/// Counts fresh detector misses before clearing a target permanently.
class FollowTargetTrackingProgress {
  FollowTargetTrackingPhase phase = FollowTargetTrackingPhase.idle;
  int missedDetectionCount = 0;

  void markSelecting() {
    phase = FollowTargetTrackingPhase.selecting;
    missedDetectionCount = 0;
  }

  void markVisible() {
    phase = FollowTargetTrackingPhase.visible;
    missedDetectionCount = 0;
  }

  void markConfirmingSelection() {
    phase = FollowTargetTrackingPhase.confirmingSelection;
    missedDetectionCount = 0;
  }

  bool recordVisibleMiss() {
    missedDetectionCount++;
    return missedDetectionCount >=
        HandGestureThresholds.followTargetLostDetectionCount;
  }

  void reset() {
    phase = FollowTargetTrackingPhase.idle;
    missedDetectionCount = 0;
  }
}
