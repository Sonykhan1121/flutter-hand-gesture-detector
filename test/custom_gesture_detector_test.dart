import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gesture_detector/hand_gesture_features/domain/services/custom_gesture_detector.dart';
import 'package:hand_detection/hand_detection.dart';

const _imageSize = Size(400, 400);

void main() {
  group('CustomGestureDetector return to main position', () {
    test('detects a small circle after five index-tip samples', () {
      final detector = CustomGestureDetector();
      final points = _circlePoints(center: const Offset(200, 130), radius: 5);

      for (final point in points.take(4)) {
        final result = detector.detect(
          hand: _indexOnlyHand(indexTip: point),
          imageSize: _imageSize,
          mirrorHorizontally: false,
        );

        expect(result.isCancelEverything, isFalse);
      }

      final result = detector.detect(
        hand: _indexOnlyHand(indexTip: points.last),
        imageSize: _imageSize,
        mirrorHorizontally: false,
      );

      expect(result.isCancelEverything, isTrue);
    });

    test('does not detect before five index-tip samples', () {
      final detector = CustomGestureDetector();
      final points = _circlePoints(center: const Offset(200, 130), radius: 5);

      for (final point in points.take(4)) {
        final result = detector.detect(
          hand: _indexOnlyHand(indexTip: point),
          imageSize: _imageSize,
          mirrorHorizontally: false,
        );

        expect(result.isCancelEverything, isFalse);
      }
    });
  });
}

List<Offset> _circlePoints({required Offset center, required double radius}) {
  return List.generate(5, (index) {
    final angle = math.pi * 2 * index / 5;
    return Offset(
      center.dx + math.cos(angle) * radius,
      center.dy + math.sin(angle) * radius,
    );
  });
}

Hand _indexOnlyHand({required Offset indexTip}) {
  const wrist = Offset(200, 260);
  const indexMcp = Offset(200, 220);
  const middleMcp = Offset(210, 225);
  const ringMcp = Offset(220, 230);
  const pinkyMcp = Offset(230, 235);

  final indexPip = Offset.lerp(indexMcp, indexTip, 0.34)!;
  final indexDip = Offset.lerp(indexMcp, indexTip, 0.67)!;

  final landmarks = <HandLandmark>[
    _landmark(HandLandmarkType.wrist, wrist),
    _landmark(HandLandmarkType.thumbMCP, const Offset(185, 230)),
    _landmark(HandLandmarkType.thumbIP, const Offset(198, 238)),
    _landmark(HandLandmarkType.thumbTip, const Offset(202, 232)),
    _landmark(HandLandmarkType.indexFingerMCP, indexMcp),
    _landmark(HandLandmarkType.indexFingerPIP, indexPip),
    _landmark(HandLandmarkType.indexFingerDIP, indexDip),
    _landmark(HandLandmarkType.indexFingerTip, indexTip),
    _landmark(HandLandmarkType.middleFingerMCP, middleMcp),
    _landmark(HandLandmarkType.middleFingerPIP, const Offset(216, 238)),
    _landmark(HandLandmarkType.middleFingerTip, const Offset(213, 229)),
    _landmark(HandLandmarkType.ringFingerMCP, ringMcp),
    _landmark(HandLandmarkType.ringFingerPIP, const Offset(226, 243)),
    _landmark(HandLandmarkType.ringFingerTip, const Offset(223, 234)),
    _landmark(HandLandmarkType.pinkyMCP, pinkyMcp),
    _landmark(HandLandmarkType.pinkyPIP, const Offset(236, 248)),
    _landmark(HandLandmarkType.pinkyTip, const Offset(233, 239)),
  ];

  return Hand(
    boundingBox: BoundingBox.ltrb(100, 80, 320, 300),
    score: 1,
    landmarks: landmarks,
    imageWidth: _imageSize.width.toInt(),
    imageHeight: _imageSize.height.toInt(),
    handedness: Handedness.right,
  );
}

HandLandmark _landmark(HandLandmarkType type, Offset point) {
  return HandLandmark(
    type: type,
    x: point.dx,
    y: point.dy,
    z: 0,
    visibility: 1,
  );
}
