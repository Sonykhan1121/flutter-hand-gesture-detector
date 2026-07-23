import '../constants/hand_gesture_thresholds.dart';
import '../models/follow_target.dart';
import 'follow_target_selector.dart';

enum FollowTargetPointingResetReason {
  none,
  poseLost,
  noCandidate,
  ambiguous,
  staleDetection,
  candidateChanged,
  fingertipOutside,
  handMissing,
  confirmationExpired,
  targetUnavailable,
}

class FollowTargetPointingDwellObservation {
  const FollowTargetPointingDwellObservation({
    required this.candidate,
    required this.progress,
    required this.freshDetectionCycles,
    required this.isComplete,
    required this.restarted,
    required this.resetReason,
  });

  final FollowTarget candidate;
  final double progress;
  final int freshDetectionCycles;
  final bool isComplete;
  final bool restarted;
  final FollowTargetPointingResetReason resetReason;
}

/// Owns the continuous 500ms identity dwell and the final-palm deadline.
class FollowTargetPointingDwellController {
  FollowTargetPointingDwellController({
    FollowTargetSelector selector = const FollowTargetSelector(),
  }) : _selector = selector;

  final FollowTargetSelector _selector;

  FollowTarget? _candidate;
  FollowTarget? _frozenTarget;
  DateTime? _startedAt;
  DateTime? _lastDetectionCycle;
  DateTime? _confirmationDeadline;
  int _freshDetectionCycles = 0;
  FollowTargetPointingResetReason _lastResetReason =
      FollowTargetPointingResetReason.none;

  FollowTarget? get candidate => _candidate;
  FollowTarget? get frozenTarget => _frozenTarget;
  DateTime? get confirmationDeadline => _confirmationDeadline;
  int get freshDetectionCycles => _freshDetectionCycles;
  FollowTargetPointingResetReason get lastResetReason => _lastResetReason;
  bool get isFrozen => _frozenTarget != null;

  double progress(DateTime now) {
    final startedAt = _startedAt;
    if (startedAt == null || now.isBefore(startedAt)) return 0;
    final milliseconds =
        HandGestureThresholds.followObjectPointingHoldDuration.inMilliseconds;
    if (milliseconds <= 0) return 1;
    return (now.difference(startedAt).inMilliseconds / milliseconds)
        .clamp(0.0, 1.0)
        .toDouble();
  }

  Duration finalPalmRemaining(DateTime now) {
    final deadline = _confirmationDeadline;
    if (deadline == null || now.isAfter(deadline)) return Duration.zero;
    return deadline.difference(now);
  }

  bool confirmationExpired(DateTime now) {
    final deadline = _confirmationDeadline;
    return deadline != null && now.isAfter(deadline);
  }

  FollowTargetPointingDwellObservation observe({
    required FollowTarget candidate,
    required DateTime detectionCycleAt,
    required DateTime now,
  }) {
    final previous = _candidate;
    var restarted = false;
    var resetReason = FollowTargetPointingResetReason.none;

    if (previous == null ||
        !_selector.isSamePointingCandidate(previous, candidate)) {
      restarted = previous != null;
      resetReason = restarted
          ? FollowTargetPointingResetReason.candidateChanged
          : FollowTargetPointingResetReason.none;
      _candidate = candidate;
      _startedAt = now;
      _lastDetectionCycle = detectionCycleAt;
      _freshDetectionCycles = 1;
      _frozenTarget = null;
      _confirmationDeadline = null;
    } else {
      _candidate = candidate;
      if (_lastDetectionCycle != detectionCycleAt) {
        _lastDetectionCycle = detectionCycleAt;
        _freshDetectionCycles += 1;
      }
    }

    final isComplete =
        progress(now) >= 1 &&
        _freshDetectionCycles >=
            HandGestureThresholds.followObjectPointingMinFreshDetectionCycles;
    if (isComplete && _frozenTarget == null) {
      _frozenTarget = _candidate;
      _confirmationDeadline = now.add(
        HandGestureThresholds.followObjectFinalPalmConfirmationDuration,
      );
    }

    _lastResetReason = resetReason;
    return FollowTargetPointingDwellObservation(
      candidate: _candidate!,
      progress: progress(now),
      freshDetectionCycles: _freshDetectionCycles,
      isComplete: isComplete,
      restarted: restarted,
      resetReason: resetReason,
    );
  }

  void updateFrozenTarget(FollowTarget target) {
    if (_frozenTarget != null) {
      _frozenTarget = target;
      _candidate = target;
    }
  }

  void reset(FollowTargetPointingResetReason reason) {
    _candidate = null;
    _frozenTarget = null;
    _startedAt = null;
    _lastDetectionCycle = null;
    _confirmationDeadline = null;
    _freshDetectionCycles = 0;
    _lastResetReason = reason;
  }

  void clear() => reset(FollowTargetPointingResetReason.none);
}
