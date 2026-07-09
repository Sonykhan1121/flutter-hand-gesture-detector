import '../constants/hand_gesture_thresholds.dart';
import '../enums/hand_move_direction.dart';

/// Keeps brief movement labels visible after detection flickers off.
class MoveDirectionDisplayHold {
  HandMoveDirection _heldDirection = HandMoveDirection.none;
  DateTime? _expiresAt;

  /// Returns the detected direction, or a held direction while it expires.
  HandMoveDirection resolve({
    required HandMoveDirection detectedDirection,
    required DateTime now,
  }) {
    if (detectedDirection == HandMoveDirection.down) {
      _heldDirection = HandMoveDirection.down;
      _expiresAt = now.add(HandGestureThresholds.movingDownDisplayHoldDuration);
      return HandMoveDirection.down;
    }

    if (detectedDirection == HandMoveDirection.up) {
      _heldDirection = HandMoveDirection.up;
      _expiresAt = now.add(HandGestureThresholds.movingUpDisplayHoldDuration);
      return HandMoveDirection.up;
    }

    if (detectedDirection != HandMoveDirection.none) {
      clear();
      return detectedDirection;
    }

    final expiresAt = _expiresAt;
    if (_heldDirection != HandMoveDirection.none &&
        expiresAt != null &&
        now.isBefore(expiresAt)) {
      return _heldDirection;
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
