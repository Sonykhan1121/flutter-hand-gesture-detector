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

      openPalm
        ..isDetected = true
        ..confidence = 0.66;
      final releaseResult = detector.update(
        _hand(box: BoundingBox.ltrb(200, 220, 320, 400)),
        now.add(const Duration(milliseconds: 1300)),
        mirrorHorizontally: false,
      );

      expect(releaseResult.isDetected, isTrue);
      expect(releaseResult.releaseReason, FollowObjectReleaseReason.openPalm);
      expect(releaseResult.releasePoint?.dx, 260);
      expect(releaseResult.releasePoint?.dy, 310);
      expect(releaseResult.gestureConfidence, closeTo(0.66, 0.001));
    });

    test('carries custom open-palm confidence while active', () {
      final openPalm = _FakeOpenPalmGestureDetector()
        ..isDetected = true
        ..confidence = 0.72;
      final detector = FollowObjectSequenceDetector(
        openPalmGestureDetector: openPalm,
      );

      final result = detector.update(
        _hand(),
        DateTime(2026),
        mirrorHorizontally: false,
      );

      expect(result.isActive, isTrue);
      expect(result.packageGestureType, GestureType.openPalm);
      expect(result.gestureConfidence, closeTo(0.72, 0.001));
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

    test('unreliable hand cannot start the open-palm hold', () {
      final openPalm = _FakeOpenPalmGestureDetector()..isDetected = true;
      final detector = FollowObjectSequenceDetector(
        openPalmGestureDetector: openPalm,
      );

      final result = detector.update(
        _hand(score: double.nan),
        DateTime(2026),
        mirrorHorizontally: false,
      );

      expect(result.isActive, isFalse);
      expect(result.isDetected, isFalse);
      expect(detector.isTargetSelectionActive, isFalse);
    });

    test('unreliable hand interrupts first open-palm hold', () {
      final openPalm = _FakeOpenPalmGestureDetector()..isDetected = true;
      final detector = FollowObjectSequenceDetector(
        openPalmGestureDetector: openPalm,
      );
      final now = DateTime(2026);

      detector.update(_hand(), now, mirrorHorizontally: false);
      final result = detector.update(
        _hand(score: 0.2),
        now.add(const Duration(milliseconds: 400)),
        mirrorHorizontally: false,
      );

      expect(result.isActive, isFalse);

      final releaseResult = detector.releaseFromLastVisiblePoint(
        now.add(const Duration(milliseconds: 500)),
      );
      expect(releaseResult.isDetected, isFalse);
    });

    test('unreliable hand while selecting target keeps last release point', () {
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
        _hand(
          box: BoundingBox.ltrb(100, 120, 220, 300),
          gestureType: GestureType.closedFist,
        ),
        now.add(const Duration(milliseconds: 1200)),
        mirrorHorizontally: false,
      );

      final unreliableResult = detector.update(
        _hand(box: BoundingBox.ltrb(300, 300, 360, 360), score: 0.2),
        now.add(const Duration(milliseconds: 1300)),
        mirrorHorizontally: false,
      );

      expect(unreliableResult.isTargetSelectionActive, isTrue);

      final releaseResult = detector.releaseFromLastVisiblePoint(
        now.add(const Duration(milliseconds: 1400)),
      );

      expect(releaseResult.isDetected, isTrue);
      expect(releaseResult.releaseReason, FollowObjectReleaseReason.handLost);
      expect(releaseResult.releasePoint?.dx, 160);
      expect(releaseResult.releasePoint?.dy, 210);
    });

    test('non-finite package confidence does not start target selection', () {
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
      final result = detector.update(
        _hand(
          gestureType: GestureType.closedFist,
          gestureConfidence: double.infinity,
        ),
        now.add(const Duration(milliseconds: 1200)),
        mirrorHorizontally: false,
      );

      expect(result.isTargetSelectionActive, isFalse);
      expect(detector.isTargetSelectionActive, isFalse);
    });
  });
}

class _FakeOpenPalmGestureDetector extends OpenPalmGestureDetector {
  bool isDetected = false;
  double confidence = 1;

  @override
  OpenPalmGestureDetectionResult detect({
    required Hand hand,
    required DateTime now,
    required bool mirrorHorizontally,
    bool allowOppositePalmSide = false,
  }) {
    return OpenPalmGestureDetectionResult(
      isDetected: isDetected,
      confidence: isDetected ? confidence : 0,
    );
  }
}

Hand _hand({
  BoundingBox? box,
  GestureType? gestureType,
  double gestureConfidence = 1,
  double score = 1,
}) {
  return Hand(
    boundingBox: box ?? BoundingBox.ltrb(100, 100, 220, 280),
    score: score,
    landmarks: [
      HandLandmark(
        type: HandLandmarkType.wrist,
        x: (box?.left ?? 100) + 10,
        y: (box?.top ?? 100) + 10,
        z: 0,
        visibility: 1,
      ),
    ],
    imageWidth: 400,
    imageHeight: 400,
    handedness: Handedness.right,
    gesture: gestureType == null
        ? null
        : GestureResult(type: gestureType, confidence: gestureConfidence),
  );
}
