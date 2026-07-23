import '../constants/hand_gesture_thresholds.dart';

enum DetectMyFaceMissResult { keepVisible, temporarilyLost, expired }

/// Owns the debounce and grace-window timing for a Detect My Face lock.
class DetectMyFaceReacquisitionController {
  bool _isActive = false;
  int _consecutiveFreshMisses = 0;
  DateTime? _firstMissAt;
  DateTime? _expiredNoticeUntil;

  bool get isActive => _isActive;
  int get consecutiveFreshMisses => _consecutiveFreshMisses;
  DateTime? get firstMissAt => _firstMissAt;

  void start() {
    _isActive = true;
    _consecutiveFreshMisses = 0;
    _firstMissAt = null;
    _expiredNoticeUntil = null;
  }

  void observeVisible() {
    if (!_isActive) return;
    _consecutiveFreshMisses = 0;
    _firstMissAt = null;
  }

  DetectMyFaceMissResult observeFreshMiss(DateTime now) {
    if (!_isActive) return DetectMyFaceMissResult.expired;

    _firstMissAt ??= now;
    _consecutiveFreshMisses++;

    if (hasExpired(now)) return DetectMyFaceMissResult.expired;
    if (_consecutiveFreshMisses >=
        HandGestureThresholds.followTargetLostDetectionCount) {
      return DetectMyFaceMissResult.temporarilyLost;
    }
    return DetectMyFaceMissResult.keepVisible;
  }

  bool hasExpired(DateTime now) {
    final firstMissAt = _firstMissAt;
    return firstMissAt != null &&
        now.difference(firstMissAt) >
            HandGestureThresholds.detectMyFaceReacquisitionDuration;
  }

  Duration remaining(DateTime now) {
    final firstMissAt = _firstMissAt;
    if (firstMissAt == null) {
      return HandGestureThresholds.detectMyFaceReacquisitionDuration;
    }

    final remaining =
        HandGestureThresholds.detectMyFaceReacquisitionDuration -
        now.difference(firstMissAt);
    return remaining.isNegative ? Duration.zero : remaining;
  }

  void markExpired(DateTime now) {
    _isActive = false;
    _consecutiveFreshMisses = 0;
    _firstMissAt = null;
    _expiredNoticeUntil = now.add(
      HandGestureThresholds.followObjectMessageHoldDuration,
    );
  }

  bool shouldShowExpiredNotice(DateTime now) {
    final until = _expiredNoticeUntil;
    return until != null && !now.isAfter(until);
  }

  void clear() {
    _isActive = false;
    _consecutiveFreshMisses = 0;
    _firstMissAt = null;
    _expiredNoticeUntil = null;
  }
}
