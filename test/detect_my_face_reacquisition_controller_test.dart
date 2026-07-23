import 'package:flutter_test/flutter_test.dart';
import 'package:gesture_detector/hand_gesture_features/domain/services/detect_my_face_reacquisition_controller.dart';

void main() {
  group('DetectMyFaceReacquisitionController', () {
    final startedAt = DateTime(2026, 7, 23, 10);

    test('keeps one fresh miss visible and waits after the second', () {
      final controller = DetectMyFaceReacquisitionController()..start();

      expect(
        controller.observeFreshMiss(startedAt),
        DetectMyFaceMissResult.keepVisible,
      );
      expect(controller.firstMissAt, startedAt);
      expect(controller.consecutiveFreshMisses, 1);

      expect(
        controller.observeFreshMiss(
          startedAt.add(const Duration(milliseconds: 100)),
        ),
        DetectMyFaceMissResult.temporarilyLost,
      );
      expect(controller.consecutiveFreshMisses, 2);
      expect(
        controller.remaining(startedAt.add(const Duration(milliseconds: 100))),
        const Duration(milliseconds: 2400),
      );
    });

    test('allows the exact 2.5 second boundary and expires after it', () {
      final controller = DetectMyFaceReacquisitionController()..start();
      controller.observeFreshMiss(startedAt);

      final exactBoundary = startedAt.add(const Duration(milliseconds: 2500));
      expect(controller.hasExpired(exactBoundary), isFalse);
      expect(controller.remaining(exactBoundary), Duration.zero);

      final afterBoundary = startedAt.add(const Duration(milliseconds: 2501));
      expect(controller.hasExpired(afterBoundary), isTrue);
      expect(controller.remaining(afterBoundary), Duration.zero);
    });

    test('a visible face clears the pending miss window', () {
      final controller = DetectMyFaceReacquisitionController()..start();
      controller.observeFreshMiss(startedAt);

      controller.observeVisible();

      expect(controller.isActive, isTrue);
      expect(controller.firstMissAt, isNull);
      expect(controller.consecutiveFreshMisses, 0);
      expect(
        controller.remaining(startedAt),
        const Duration(milliseconds: 2500),
      );
    });

    test('expired notice is temporary and clear removes all state', () {
      final controller = DetectMyFaceReacquisitionController()..start();
      controller.observeFreshMiss(startedAt);
      final expiredAt = startedAt.add(const Duration(milliseconds: 2501));

      controller.markExpired(expiredAt);

      expect(controller.isActive, isFalse);
      expect(controller.shouldShowExpiredNotice(expiredAt), isTrue);
      expect(
        controller.shouldShowExpiredNotice(
          expiredAt.add(const Duration(milliseconds: 1201)),
        ),
        isFalse,
      );

      controller.clear();
      expect(controller.shouldShowExpiredNotice(expiredAt), isFalse);
      expect(controller.firstMissAt, isNull);
    });
  });
}
