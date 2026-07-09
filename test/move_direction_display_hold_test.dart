import 'package:flutter_test/flutter_test.dart';
import 'package:gesture_detector/hand_gesture_features/domain/constants/hand_gesture_thresholds.dart';
import 'package:gesture_detector/hand_gesture_features/domain/enums/hand_move_direction.dart';
import 'package:gesture_detector/hand_gesture_features/domain/services/move_direction_display_hold.dart';

void main() {
  group('MoveDirectionDisplayHold', () {
    late MoveDirectionDisplayHold hold;
    late DateTime now;

    setUp(() {
      hold = MoveDirectionDisplayHold();
      now = DateTime(2026, 7, 8, 10);
    });

    test('shows down immediately when detected', () {
      expect(
        hold.resolve(detectedDirection: HandMoveDirection.down, now: now),
        HandMoveDirection.down,
      );
    });

    test('keeps down visible inside the display hold window', () {
      hold.resolve(detectedDirection: HandMoveDirection.down, now: now);

      expect(
        hold.resolve(
          detectedDirection: HandMoveDirection.none,
          now: now.add(
            HandGestureThresholds.movingDownDisplayHoldDuration -
                const Duration(milliseconds: 1),
          ),
        ),
        HandMoveDirection.down,
      );
    });

    test('expires down after the display hold window', () {
      hold.resolve(detectedDirection: HandMoveDirection.down, now: now);

      expect(
        hold.resolve(
          detectedDirection: HandMoveDirection.none,
          now: now.add(HandGestureThresholds.movingDownDisplayHoldDuration),
        ),
        HandMoveDirection.none,
      );
    });

    test('shows up immediately when detected', () {
      expect(
        hold.resolve(detectedDirection: HandMoveDirection.up, now: now),
        HandMoveDirection.up,
      );
    });

    test('keeps up visible inside the display hold window', () {
      hold.resolve(detectedDirection: HandMoveDirection.up, now: now);

      expect(
        hold.resolve(
          detectedDirection: HandMoveDirection.none,
          now: now.add(
            HandGestureThresholds.movingUpDisplayHoldDuration -
                const Duration(milliseconds: 1),
          ),
        ),
        HandMoveDirection.up,
      );
    });

    test('expires up after the display hold window', () {
      hold.resolve(detectedDirection: HandMoveDirection.up, now: now);

      expect(
        hold.resolve(
          detectedDirection: HandMoveDirection.none,
          now: now.add(HandGestureThresholds.movingUpDisplayHoldDuration),
        ),
        HandMoveDirection.none,
      );
    });

    test('left or right direction clears held display', () {
      hold.resolve(detectedDirection: HandMoveDirection.down, now: now);

      expect(
        hold.resolve(
          detectedDirection: HandMoveDirection.left,
          now: now.add(const Duration(milliseconds: 100)),
        ),
        HandMoveDirection.left,
      );
      expect(
        hold.resolve(
          detectedDirection: HandMoveDirection.none,
          now: now.add(const Duration(milliseconds: 200)),
        ),
        HandMoveDirection.none,
      );
    });

    test('clear suppresses held down display', () {
      hold.resolve(detectedDirection: HandMoveDirection.down, now: now);

      hold.clear();

      expect(
        hold.resolve(
          detectedDirection: HandMoveDirection.none,
          now: now.add(const Duration(milliseconds: 100)),
        ),
        HandMoveDirection.none,
      );
    });
  });
}
