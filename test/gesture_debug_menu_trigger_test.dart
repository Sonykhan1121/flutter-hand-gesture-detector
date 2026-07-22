import 'package:flutter_test/flutter_test.dart';
import 'package:gesture_detector/hand_gesture_features/domain/services/gesture_debug_menu_trigger.dart';

void main() {
  group('GestureDebugMenuTrigger', () {
    test('opens once on exactly the third Love You frame', () {
      final trigger = GestureDebugMenuTrigger();

      expect(trigger.update(isLoveYou: true), isFalse);
      expect(trigger.update(isLoveYou: true), isFalse);
      expect(trigger.update(isLoveYou: true), isTrue);
      expect(trigger.isLatched, isTrue);
      expect(trigger.update(isLoveYou: true), isFalse);
    });

    test('requires a confirmed release before it can open again', () {
      final trigger = GestureDebugMenuTrigger();

      for (var frame = 0; frame < 3; frame += 1) {
        trigger.update(isLoveYou: true);
      }
      expect(trigger.isLatched, isTrue);

      expect(trigger.update(isLoveYou: false), isFalse);
      expect(trigger.update(isLoveYou: false), isFalse);
      expect(trigger.isLatched, isTrue);
      expect(trigger.update(isLoveYou: true), isFalse);

      for (var frame = 0; frame < 3; frame += 1) {
        trigger.update(isLoveYou: false);
      }
      expect(trigger.isLatched, isFalse);

      expect(trigger.update(isLoveYou: true), isFalse);
      expect(trigger.update(isLoveYou: true), isFalse);
      expect(trigger.update(isLoveYou: true), isTrue);
    });

    test('interrupted confirmation restarts from frame one', () {
      final trigger = GestureDebugMenuTrigger();

      expect(trigger.update(isLoveYou: true), isFalse);
      expect(trigger.update(isLoveYou: true), isFalse);
      expect(trigger.update(isLoveYou: false), isFalse);
      expect(trigger.update(isLoveYou: true), isFalse);
      expect(trigger.update(isLoveYou: true), isFalse);
      expect(trigger.update(isLoveYou: true), isTrue);
    });

    test('clear removes partial confirmation and latch state', () {
      final trigger = GestureDebugMenuTrigger();

      trigger.update(isLoveYou: true);
      trigger.update(isLoveYou: true);
      trigger.clear();

      expect(trigger.isLatched, isFalse);
      expect(trigger.update(isLoveYou: true), isFalse);
      expect(trigger.update(isLoveYou: true), isFalse);
      expect(trigger.update(isLoveYou: true), isTrue);
    });
  });
}
