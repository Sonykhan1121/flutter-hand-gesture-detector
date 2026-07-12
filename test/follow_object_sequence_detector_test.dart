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

    for (final extendedFingerCount in const [1, 2]) {
      test('final release accepts $extendedFingerCount extended finger(s) '
          'after two reliable frames', () {
        final openPalm = _FakeOpenPalmGestureDetector();
        final detector = FollowObjectSequenceDetector(
          openPalmGestureDetector: openPalm,
        );
        final now = DateTime(2026);
        _startTargetSelection(detector, openPalm, now);

        final firstFrame = detector.update(
          _relaxedReleaseHand(extendedFingerCount: extendedFingerCount),
          now.add(const Duration(milliseconds: 1300)),
          mirrorHorizontally: false,
        );
        expect(firstFrame.isDetected, isFalse);
        expect(firstFrame.isTargetSelectionActive, isTrue);

        final releaseResult = detector.update(
          _relaxedReleaseHand(
            extendedFingerCount: extendedFingerCount,
            box: BoundingBox.ltrb(160, 180, 320, 400),
          ),
          now.add(const Duration(milliseconds: 1400)),
          mirrorHorizontally: false,
        );

        expect(releaseResult.isDetected, isTrue);
        expect(releaseResult.releaseReason, FollowObjectReleaseReason.openPalm);
        expect(releaseResult.releasePoint?.dx, 240);
        expect(releaseResult.releasePoint?.dy, 290);
        expect(detector.isTargetSelectionActive, isFalse);
      });
    }

    test('closed-fist classification prevents accidental relaxed release', () {
      final openPalm = _FakeOpenPalmGestureDetector();
      final detector = FollowObjectSequenceDetector(
        openPalmGestureDetector: openPalm,
      );
      final now = DateTime(2026);
      _startTargetSelection(detector, openPalm, now);

      for (var frame = 0; frame < 3; frame++) {
        final result = detector.update(
          _relaxedReleaseHand(
            extendedFingerCount: 2,
            gestureType: GestureType.closedFist,
          ),
          now.add(Duration(milliseconds: 1300 + frame * 100)),
          mirrorHorizontally: false,
        );
        expect(result.isDetected, isFalse);
        expect(result.isTargetSelectionActive, isTrue);
      }
    });

    test('an interrupted relaxed pose restarts frame confirmation', () {
      final openPalm = _FakeOpenPalmGestureDetector();
      final detector = FollowObjectSequenceDetector(
        openPalmGestureDetector: openPalm,
      );
      final now = DateTime(2026);
      _startTargetSelection(detector, openPalm, now);

      detector.update(
        _relaxedReleaseHand(extendedFingerCount: 1),
        now.add(const Duration(milliseconds: 1300)),
        mirrorHorizontally: false,
      );
      detector.update(
        _relaxedReleaseHand(extendedFingerCount: 0),
        now.add(const Duration(milliseconds: 1400)),
        mirrorHorizontally: false,
      );
      final restarted = detector.update(
        _relaxedReleaseHand(extendedFingerCount: 1),
        now.add(const Duration(milliseconds: 1500)),
        mirrorHorizontally: false,
      );

      expect(restarted.isDetected, isFalse);
      expect(restarted.isTargetSelectionActive, isTrue);
      expect(
        detector
            .update(
              _relaxedReleaseHand(extendedFingerCount: 1),
              now.add(const Duration(milliseconds: 1600)),
              mirrorHorizontally: false,
            )
            .isDetected,
        isTrue,
      );
    });

    test('a partly straightened single finger is enough for final release', () {
      final openPalm = _FakeOpenPalmGestureDetector();
      final detector = FollowObjectSequenceDetector(
        openPalmGestureDetector: openPalm,
      );
      final now = DateTime(2026);
      _startTargetSelection(detector, openPalm, now);

      final hand = _relaxedReleaseHand(
        extendedFingerCount: 1,
        partiallyStraightened: true,
      );
      expect(
        detector
            .update(
              hand,
              now.add(const Duration(milliseconds: 1300)),
              mirrorHorizontally: false,
            )
            .isDetected,
        isFalse,
      );
      expect(
        detector
            .update(
              hand,
              now.add(const Duration(milliseconds: 1400)),
              mirrorHorizontally: false,
            )
            .isDetected,
        isTrue,
      );
    });

    test('carries custom open-palm confidence while active', () {
      final openPalm =
          _FakeOpenPalmGestureDetector()
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

void _startTargetSelection(
  FollowObjectSequenceDetector detector,
  _FakeOpenPalmGestureDetector openPalm,
  DateTime now,
) {
  openPalm.isDetected = true;
  detector.update(_hand(), now, mirrorHorizontally: false);
  detector.update(
    _hand(),
    now.add(const Duration(seconds: 1)),
    mirrorHorizontally: false,
  );
  openPalm.isDetected = false;
  final result = detector.update(
    _hand(gestureType: GestureType.closedFist),
    now.add(const Duration(milliseconds: 1200)),
    mirrorHorizontally: false,
  );
  expect(result.isTargetSelectionActive, isTrue);
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
    gesture:
        gestureType == null
            ? null
            : GestureResult(type: gestureType, confidence: gestureConfidence),
  );
}

Hand _relaxedReleaseHand({
  required int extendedFingerCount,
  BoundingBox? box,
  GestureType? gestureType,
  bool partiallyStraightened = false,
}) {
  final boundingBox = box ?? BoundingBox.ltrb(100, 80, 300, 340);
  final landmarks = <HandLandmark>[_landmark(HandLandmarkType.wrist, 200, 310)];
  final chains = const [
    [
      HandLandmarkType.indexFingerMCP,
      HandLandmarkType.indexFingerPIP,
      HandLandmarkType.indexFingerDIP,
      HandLandmarkType.indexFingerTip,
    ],
    [
      HandLandmarkType.middleFingerMCP,
      HandLandmarkType.middleFingerPIP,
      HandLandmarkType.middleFingerDIP,
      HandLandmarkType.middleFingerTip,
    ],
    [
      HandLandmarkType.ringFingerMCP,
      HandLandmarkType.ringFingerPIP,
      HandLandmarkType.ringFingerDIP,
      HandLandmarkType.ringFingerTip,
    ],
    [
      HandLandmarkType.pinkyMCP,
      HandLandmarkType.pinkyPIP,
      HandLandmarkType.pinkyDIP,
      HandLandmarkType.pinkyTip,
    ],
  ];

  for (var index = 0; index < chains.length; index++) {
    final x = 140.0 + index * 40;
    final extended = index < extendedFingerCount;
    final relaxedBent = extended && partiallyStraightened && index == 0;
    landmarks.addAll([
      _landmark(chains[index][0], x, 240),
      _landmark(chains[index][1], x, 200),
      _landmark(
        chains[index][2],
        relaxedBent ? x + 15 : x,
        relaxedBent ? 174 : (extended ? 150 : 220),
      ),
      _landmark(
        chains[index][3],
        relaxedBent ? x + 30 : x,
        relaxedBent ? 148 : (extended ? 100 : 245),
      ),
    ]);
  }

  return Hand(
    boundingBox: boundingBox,
    score: 1,
    landmarks: landmarks,
    imageWidth: 400,
    imageHeight: 400,
    handedness: Handedness.right,
    gesture:
        gestureType == null
            ? null
            : GestureResult(type: gestureType, confidence: 1),
  );
}

HandLandmark _landmark(HandLandmarkType type, double x, double y) {
  return HandLandmark(type: type, x: x, y: y, z: 0, visibility: 1);
}
