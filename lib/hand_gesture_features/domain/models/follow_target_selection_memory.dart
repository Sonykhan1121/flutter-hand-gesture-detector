import 'dart:ui';

import '../constants/hand_gesture_thresholds.dart';
import 'follow_target.dart';

/// Short-lived snapshot of the exact candidate shown during target selection.
class FollowTargetSelectionMemory {
  const FollowTargetSelectionMemory({
    required this.candidate,
    required this.lastDetectionCycle,
    required this.lastSeenAt,
    required this.lastHandPoint,
    required this.consecutiveConfirmationCount,
  });

  final FollowTarget candidate;
  final DateTime lastDetectionCycle;
  final DateTime lastSeenAt;
  final Offset lastHandPoint;
  final int consecutiveConfirmationCount;

  bool get isReleasable =>
      consecutiveConfirmationCount >=
      HandGestureThresholds.followTargetSelectionConfirmationCycles;

  bool isValid({required DateTime now, required Offset handPoint}) {
    final age = now.difference(lastSeenAt);
    return !age.isNegative &&
        age <= HandGestureThresholds.followTargetSelectionMemoryDuration &&
        (handPoint - lastHandPoint).distance <=
            HandGestureThresholds.followTargetSelectionMaxHandMovement;
  }

  factory FollowTargetSelectionMemory.firstObservation({
    required FollowTarget candidate,
    required DateTime observedAt,
    required Offset handPoint,
    DateTime? detectionCycleAt,
  }) {
    return FollowTargetSelectionMemory(
      candidate: candidate,
      lastDetectionCycle: detectionCycleAt ?? candidate.detectedAt,
      lastSeenAt: observedAt,
      lastHandPoint: handPoint,
      consecutiveConfirmationCount: 1,
    );
  }

  /// Records only a genuinely new detector cycle, not a reused cached result.
  FollowTargetSelectionMemory observeFreshCycle({
    required FollowTarget candidate,
    required DateTime observedAt,
    required Offset handPoint,
    DateTime? detectionCycleAt,
  }) {
    final cycleAt = detectionCycleAt ?? candidate.detectedAt;
    if (cycleAt == lastDetectionCycle) return this;
    return FollowTargetSelectionMemory(
      candidate: candidate,
      lastDetectionCycle: cycleAt,
      lastSeenAt: observedAt,
      lastHandPoint: handPoint,
      consecutiveConfirmationCount: consecutiveConfirmationCount + 1,
    );
  }
}

/// Result of reconciling live detections with the short selection memory.
class FollowTargetSelectionMemoryUpdate {
  const FollowTargetSelectionMemoryUpdate({
    required this.memory,
    required this.isCandidateHidden,
  });

  final FollowTargetSelectionMemory? memory;
  final bool isCandidateHidden;

  FollowTarget? get candidate => memory?.candidate;
}
