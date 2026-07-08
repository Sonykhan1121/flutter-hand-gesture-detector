import '../constants/hand_gesture_thresholds.dart';
import '../enums/hand_move_direction.dart';

/// Keeps the "moving down" label visible briefly after detection flickers off.
class MoveDirectionDisplayHold {
  HandMoveDirection _heldDirection = HandMoveDirection.none;
  DateTime? _expiresAt;

  /// Returns the detected direction, or a held-down direction while it expires.
  HandMoveDirection resolve({
    required HandMoveDirection detectedDirection,
    required DateTime now,
  }) {
    if (detectedDirection == HandMoveDirection.down) {
      _heldDirection = HandMoveDirection.down;
      _expiresAt = now.add(HandGestureThresholds.movingDownDisplayHoldDuration);
      return HandMoveDirection.down;
    }

    if (detectedDirection != HandMoveDirection.none) {
      clear();
      return detectedDirection;
    }

    final expiresAt = _expiresAt;
    if (_heldDirection == HandMoveDirection.down &&
        expiresAt != null &&
        now.isBefore(expiresAt)) {
      return HandMoveDirection.down;
    }

    clear();
    return HandMoveDirection.none;
  }

  /// Clears any held display direction.
  void clear() {
    _heldDirection = HandMoveDirection.none;
    _expiresAt = null;
  }
}
