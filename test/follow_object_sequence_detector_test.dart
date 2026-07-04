import 'package:flutter_test/flutter_test.dart';
import 'package:gesture_detector/hand_gesture_features/domain/enums/follow_object_release_reason.dart';
import 'package:gesture_detector/hand_gesture_features/domain/models/open_palm_gesture_detection_result.dart';
import 'package:gesture_detector/hand_gesture_features/domain/services/follow_object_sequence_detector.dart';
import 'package:gesture_detector/hand_gesture_features/domain/services/open_palm_gesture_detector.dart';
import 'package:hand_detection/hand_detection.dart';

void main() {
  group('FollowObjectSequenceDetector', () {
    test(
      'releases from last visible hand center when hand is lost after closed fist',
      () {
        final openPalm = _FakeOpenPalmGestureDetector();
        final detector = FollowObjectSequenceDetector(
          openPalmGestureDetector: openPalm,
        );
        final now = DateTime(2026);

        openPalm.isDetected = true;
        detector.update(_hand(), now, mirrorHorizontally: false);
        detector.update(
          _hand(),
          now.add(const Duration(seconds: 1)),
          mirrorHorizontally: false,
        );

        openPalm.isDetected = false;
        final activeResult = detector.update(
          _hand(
            box: BoundingBox.ltrb(100, 120, 220, 300),
            gestureType: GestureType.closedFist,
          ),
          now.add(const Duration(milliseconds: 1200)),
          mirrorHorizontally: false,
        );

        expect(activeResult.isTargetSelectionActive, isTrue);

        detector.update(
          _hand(box: BoundingBox.ltrb(140, 180, 260, 360)),
          now.add(const Duration(milliseconds: 1300)),
          mirrorHorizontally: false,
        );

        final releaseResult = detector.releaseFromLastVisiblePoint(
          now.add(const Duration(milliseconds: 1400)),
        );

        expect(releaseResult.isDetected, isTrue);
        expect(releaseResult.releaseReason, FollowObjectReleaseReason.handLost);
        expect(releaseResult.releasePoint?.dx, 200);
        expect(releaseResult.releasePoint?.dy, 270);
        expect(detector.isTargetSelectionActive, isFalse);
      },
    );

    test('final open palm release uses the current hand center', () {
      final openPalm = _FakeOpenPalmGestureDetector();
      final detector = FollowObjectSequenceDetector(
        openPalmGestureDetector: openPalm,
      );
      final now = DateTime(2026);

      openPalm.isDetected = true;
      detector.update(_hand(), now, mirrorHorizontally: false);
      detector.update(
        _hand(),
        now.add(const Duration(seconds: 1)),
        mirrorHorizontally: false,
      );

      openPalm.isDetected = false;
      detector.update(
        _hand(gestureType: GestureType.closedFist),
        now.add(const Duration(milliseconds: 1200)),
        mirrorHorizontally: false,
      );

      openPalm.isDetected = true;
      final releaseResult = detector.update(
        _hand(box: BoundingBox.ltrb(200, 220, 320, 400)),
        now.add(const Duration(milliseconds: 1300)),
        mirrorHorizontally: false,
      );

      expect(releaseResult.isDetected, isTrue);
      expect(releaseResult.releaseReason, FollowObjectReleaseReason.openPalm);
      expect(releaseResult.releasePoint?.dx, 260);
      expect(releaseResult.releasePoint?.dy, 310);
    });

    test('hand lost before closed fist clears without release', () {
      final openPalm = _FakeOpenPalmGestureDetector();
      final detector = FollowObjectSequenceDetector(
        openPalmGestureDetector: openPalm,
      );
      final now = DateTime(2026);

      openPalm.isDetected = true;
      detector.update(_hand(), now, mirrorHorizontally: false);
      detector.update(
        _hand(),
        now.add(const Duration(seconds: 1)),
        mirrorHorizontally: false,
      );

      final releaseResult = detector.releaseFromLastVisiblePoint(
        now.add(const Duration(milliseconds: 1200)),
      );

      expect(releaseResult.isDetected, isFalse);
      expect(releaseResult.releasePoint, isNull);
      expect(detector.isTargetSelectionActive, isFalse);
    });
  });
}

class _FakeOpenPalmGestureDetector extends OpenPalmGestureDetector {
  bool isDetected = false;

  @override
  OpenPalmGestureDetectionResult detect({
    required Hand hand,
    required DateTime now,
    required bool mirrorHorizontally,
    bool allowOppositePalmSide = false,
  }) {
    return OpenPalmGestureDetectionResult(
      isDetected: isDetected,
      confidence: isDetected ? 1 : 0,
    );
  }
}

Hand _hand({BoundingBox? box, GestureType? gestureType}) {
  return Hand(
    boundingBox: box ?? BoundingBox.ltrb(100, 100, 220, 280),
    score: 1,
    landmarks: const [],
    imageWidth: 400,
    imageHeight: 400,
    handedness: Handedness.right,
    gesture:
        gestureType == null
            ? null
            : GestureResult(type: gestureType, confidence: 1),
  );
}
