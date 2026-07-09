import 'package:flutter_test/flutter_test.dart';
import 'package:gesture_detector/hand_gesture_features/domain/services/open_palm_gesture_detector.dart';
import 'package:hand_detection/hand_detection.dart';

void main() {
  group('OpenPalmGestureDetector', () {
    test('detects open palm when index and middle chains go upward', () {
      final detector = OpenPalmGestureDetector();
      final hand = _openPalmHand();

      expect(_detectAfterSmoothing(detector, hand).isDetected, isTrue);
    });

    test('detects open palm when fingertips are close but distinct', () {
      final detector = OpenPalmGestureDetector();
      final hand = _openPalmHand(
        middlePip: const Offset(167, 155),
        middleDip: const Offset(150, 110),
        middleTip: const Offset(136, 72),
      );

      expect(_detectAfterSmoothing(detector, hand).isDetected, isTrue);
    });

    test('rejects open palm when index tip overlaps middle tip', () {
      final detector = OpenPalmGestureDetector();
      final result = _detectAfterSmoothing(
        detector,
        _openPalmHand(middleTip: const Offset(132, 68)),
      );

      expect(result.isDetected, isFalse);
      expect(result.confidence, 0);
    });

    test('rejects open palm when thumb tip overlaps index tip', () {
      final detector = OpenPalmGestureDetector();
      final result = _detectAfterSmoothing(
        detector,
        _openPalmHand(thumbTip: const Offset(132, 68)),
      );

      expect(result.isDetected, isFalse);
      expect(result.confidence, 0);
    });

    test('rejects open palm when ring tip overlaps pinky tip', () {
      final detector = OpenPalmGestureDetector();
      final result = _detectAfterSmoothing(
        detector,
        _openPalmHand(pinkyTip: const Offset(240, 72)),
      );

      expect(result.isDetected, isFalse);
      expect(result.confidence, 0);
    });

    test('rejects open palm when index tip overlaps ring finger joint', () {
      final detector = OpenPalmGestureDetector();
      final result = _detectAfterSmoothing(
        detector,
        _openPalmHand(ringDip: const Offset(132, 68)),
      );

      expect(result.isDetected, isFalse);
      expect(result.confidence, 0);
    });

    test('rejects open palm when one joint overlaps another joint', () {
      final detector = OpenPalmGestureDetector();
      final result = _detectAfterSmoothing(
        detector,
        _openPalmHand(ringPip: const Offset(185, 135)),
      );

      expect(result.isDetected, isFalse);
      expect(result.confidence, 0);
    });

    test('rejects open palm when wrist overlaps another landmark', () {
      final detector = OpenPalmGestureDetector();
      final result = _detectAfterSmoothing(
        detector,
        _openPalmHand(wrist: const Offset(150, 250)),
      );

      expect(result.isDetected, isFalse);
      expect(result.confidence, 0);
    });

    test('overlapping current frame suppresses previous valid smoothing', () {
      final detector = OpenPalmGestureDetector();
      final start = DateTime(2026);

      detector.detect(
        hand: _openPalmHand(),
        now: start,
        mirrorHorizontally: false,
      );
      expect(
        detector
            .detect(
              hand: _openPalmHand(),
              now: start.add(const Duration(milliseconds: 100)),
              mirrorHorizontally: false,
            )
            .isDetected,
        isTrue,
      );

      final overlapResult = detector.detect(
        hand: _openPalmHand(middleTip: const Offset(132, 68)),
        now: start.add(const Duration(milliseconds: 200)),
        mirrorHorizontally: false,
      );

      expect(overlapResult.isDetected, isFalse);
      expect(overlapResult.confidence, 0);
    });

    test('rejects open palm when index and middle chains do not go upward', () {
      final detector = OpenPalmGestureDetector();
      final hand = _openPalmHand(
        indexPip: const Offset(144, 255),
        indexDip: const Offset(138, 288),
        indexTip: const Offset(132, 322),
        middlePip: const Offset(185, 250),
        middleDip: const Offset(185, 288),
        middleTip: const Offset(185, 326),
      );

      expect(_detectAfterSmoothing(detector, hand).isDetected, isFalse);
    });

    test('invalid hand confidence resets smoothing', () {
      final detector = OpenPalmGestureDetector();
      final start = DateTime(2026);

      detector.detect(
        hand: _openPalmHand(),
        now: start,
        mirrorHorizontally: false,
      );

      final invalidResult = detector.detect(
        hand: _openPalmHand(score: double.infinity),
        now: start.add(const Duration(milliseconds: 100)),
        mirrorHorizontally: false,
      );

      expect(invalidResult.isDetected, isFalse);
      expect(invalidResult.confidence, 0);

      final nextValidResult = detector.detect(
        hand: _openPalmHand(),
        now: start.add(const Duration(milliseconds: 200)),
        mirrorHorizontally: false,
      );

      expect(nextValidResult.isDetected, isFalse);
    });
  });
}

dynamic _detectAfterSmoothing(OpenPalmGestureDetector detector, Hand hand) {
  final start = DateTime(2026);

  detector.detect(hand: hand, now: start, mirrorHorizontally: false);

  return detector.detect(
    hand: hand,
    now: start.add(const Duration(milliseconds: 100)),
    mirrorHorizontally: false,
  );
}

Hand _openPalmHand({
  Offset wrist = const Offset(200, 330),
  Offset thumbCmc = const Offset(170, 292),
  Offset thumbMcp = const Offset(150, 250),
  Offset thumbIp = const Offset(112, 210),
  Offset thumbTip = const Offset(74, 178),
  Offset indexMcp = const Offset(155, 225),
  Offset indexPip = const Offset(144, 155),
  Offset indexDip = const Offset(138, 110),
  Offset indexTip = const Offset(132, 68),
  Offset middleMcp = const Offset(185, 212),
  Offset middlePip = const Offset(185, 135),
  Offset middleDip = const Offset(185, 90),
  Offset middleTip = const Offset(185, 48),
  Offset ringMcp = const Offset(215, 216),
  Offset ringPip = const Offset(226, 150),
  Offset ringDip = const Offset(234, 110),
  Offset ringTip = const Offset(240, 72),
  Offset pinkyMcp = const Offset(245, 232),
  Offset pinkyPip = const Offset(270, 178),
  Offset pinkyDip = const Offset(286, 146),
  Offset pinkyTip = const Offset(298, 118),
  double score = 1,
}) {
  return _handWithLandmarks({
    HandLandmarkType.wrist: wrist,
    HandLandmarkType.thumbCMC: thumbCmc,
    HandLandmarkType.thumbMCP: thumbMcp,
    HandLandmarkType.thumbIP: thumbIp,
    HandLandmarkType.thumbTip: thumbTip,
    HandLandmarkType.indexFingerMCP: indexMcp,
    HandLandmarkType.indexFingerPIP: indexPip,
    HandLandmarkType.indexFingerDIP: indexDip,
    HandLandmarkType.indexFingerTip: indexTip,
    HandLandmarkType.middleFingerMCP: middleMcp,
    HandLandmarkType.middleFingerPIP: middlePip,
    HandLandmarkType.middleFingerDIP: middleDip,
    HandLandmarkType.middleFingerTip: middleTip,
    HandLandmarkType.ringFingerMCP: ringMcp,
    HandLandmarkType.ringFingerPIP: ringPip,
    HandLandmarkType.ringFingerDIP: ringDip,
    HandLandmarkType.ringFingerTip: ringTip,
    HandLandmarkType.pinkyMCP: pinkyMcp,
    HandLandmarkType.pinkyPIP: pinkyPip,
    HandLandmarkType.pinkyDIP: pinkyDip,
    HandLandmarkType.pinkyTip: pinkyTip,
  }, score: score);
}

Hand _handWithLandmarks(
  Map<HandLandmarkType, Offset> points, {
  double score = 1,
}) {
  return Hand(
    boundingBox: BoundingBox.ltrb(60, 40, 320, 340),
    score: score,
    landmarks: points.entries
        .map(
          (entry) => HandLandmark(
            type: entry.key,
            x: entry.value.dx,
            y: entry.value.dy,
            z: 0,
            visibility: 1,
          ),
        )
        .toList(growable: false),
    imageWidth: 400,
    imageHeight: 400,
    handedness: Handedness.right,
  );
}
