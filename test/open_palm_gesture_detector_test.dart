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
  Offset indexPip = const Offset(144, 155),
  Offset indexDip = const Offset(138, 110),
  Offset indexTip = const Offset(132, 68),
  Offset middlePip = const Offset(185, 135),
  Offset middleDip = const Offset(185, 90),
  Offset middleTip = const Offset(185, 48),
}) {
  return _handWithLandmarks({
    HandLandmarkType.wrist: const Offset(200, 330),
    HandLandmarkType.thumbMCP: const Offset(150, 250),
    HandLandmarkType.thumbIP: const Offset(112, 210),
    HandLandmarkType.thumbTip: const Offset(74, 178),
    HandLandmarkType.indexFingerMCP: const Offset(155, 225),
    HandLandmarkType.indexFingerPIP: indexPip,
    HandLandmarkType.indexFingerDIP: indexDip,
    HandLandmarkType.indexFingerTip: indexTip,
    HandLandmarkType.middleFingerMCP: const Offset(185, 212),
    HandLandmarkType.middleFingerPIP: middlePip,
    HandLandmarkType.middleFingerDIP: middleDip,
    HandLandmarkType.middleFingerTip: middleTip,
    HandLandmarkType.ringFingerMCP: const Offset(215, 216),
    HandLandmarkType.ringFingerPIP: const Offset(226, 150),
    HandLandmarkType.ringFingerTip: const Offset(240, 72),
    HandLandmarkType.pinkyMCP: const Offset(245, 232),
    HandLandmarkType.pinkyPIP: const Offset(270, 178),
    HandLandmarkType.pinkyTip: const Offset(298, 118),
  });
}

Hand _handWithLandmarks(Map<HandLandmarkType, Offset> points) {
  return Hand(
    boundingBox: BoundingBox.ltrb(60, 40, 320, 340),
    score: 1,
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
