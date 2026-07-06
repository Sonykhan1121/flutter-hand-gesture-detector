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

  group('CustomGestureDetector punch', () {
    test('detects punch immediately when all fingers are closed', () {
      final detector = CustomGestureDetector();

      final result = detector.detect(
        hand: _punchHand(),
        imageSize: _imageSize,
        mirrorHorizontally: false,
      );

      expect(result.isPunch, isTrue);
    });

    test('does not punch when fingers are open', () {
      final detector = CustomGestureDetector();

      final result = detector.detect(
        hand: _punchHand(fingersCurled: false),
        imageSize: _imageSize,
        mirrorHorizontally: false,
      );

      expect(result.isPunch, isFalse);
    });

    test('package closed fist support still requires closed fingers', () {
      final detector = CustomGestureDetector();

      final result = detector.detect(
        hand: _punchHand(
          fingersCurled: false,
          gesture: const GestureResult(
            type: GestureType.closedFist,
            confidence: 1,
          ),
        ),
        imageSize: _imageSize,
        mirrorHorizontally: false,
      );

      expect(result.isPunch, isFalse);
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

Hand _punchHand({
  bool fingersCurled = true,
  bool thumbTucked = true,
  double scale = 1,
  Offset palmOffset = Offset.zero,
  GestureResult? gesture,
}) {
  const basePalmCenter = Offset(204, 220);

  Offset point(Offset base) {
    return Offset(
      basePalmCenter.dx + (base.dx - basePalmCenter.dx) * scale + palmOffset.dx,
      basePalmCenter.dy + (base.dy - basePalmCenter.dy) * scale + palmOffset.dy,
    );
  }

  const wrist = Offset(200, 300);
  const thumbMcp = Offset(230, 230);
  const thumbIp = Offset(210, 238);
  final thumbTip = thumbTucked
      ? const Offset(190, 240)
      : const Offset(300, 235);
  const indexMcp = Offset(160, 200);
  const middleMcp = Offset(190, 200);
  const ringMcp = Offset(220, 200);
  const pinkyMcp = Offset(250, 200);

  final indexPip = fingersCurled
      ? const Offset(160, 245)
      : const Offset(160, 150);
  final indexTip = fingersCurled
      ? const Offset(205, 265)
      : const Offset(160, 90);
  final middlePip = fingersCurled
      ? const Offset(190, 245)
      : const Offset(190, 145);
  final middleTip = fingersCurled
      ? const Offset(230, 260)
      : const Offset(190, 80);
  final ringPip = fingersCurled
      ? const Offset(220, 245)
      : const Offset(220, 145);
  final ringTip = fingersCurled
      ? const Offset(180, 260)
      : const Offset(220, 80);
  final pinkyPip = fingersCurled
      ? const Offset(250, 245)
      : const Offset(250, 150);
  final pinkyTip = fingersCurled
      ? const Offset(205, 260)
      : const Offset(250, 90);

  final landmarks = <HandLandmark>[
    _landmark(HandLandmarkType.wrist, point(wrist)),
    _landmark(HandLandmarkType.thumbMCP, point(thumbMcp)),
    _landmark(HandLandmarkType.thumbIP, point(thumbIp)),
    _landmark(HandLandmarkType.thumbTip, point(thumbTip)),
    _landmark(HandLandmarkType.indexFingerMCP, point(indexMcp)),
    _landmark(HandLandmarkType.indexFingerPIP, point(indexPip)),
    _landmark(
      HandLandmarkType.indexFingerDIP,
      Offset.lerp(point(indexPip), point(indexTip), 0.5)!,
    ),
    _landmark(HandLandmarkType.indexFingerTip, point(indexTip)),
    _landmark(HandLandmarkType.middleFingerMCP, point(middleMcp)),
    _landmark(HandLandmarkType.middleFingerPIP, point(middlePip)),
    _landmark(
      HandLandmarkType.middleFingerDIP,
      Offset.lerp(point(middlePip), point(middleTip), 0.5)!,
    ),
    _landmark(HandLandmarkType.middleFingerTip, point(middleTip)),
    _landmark(HandLandmarkType.ringFingerMCP, point(ringMcp)),
    _landmark(HandLandmarkType.ringFingerPIP, point(ringPip)),
    _landmark(
      HandLandmarkType.ringFingerDIP,
      Offset.lerp(point(ringPip), point(ringTip), 0.5)!,
    ),
    _landmark(HandLandmarkType.ringFingerTip, point(ringTip)),
    _landmark(HandLandmarkType.pinkyMCP, point(pinkyMcp)),
    _landmark(HandLandmarkType.pinkyPIP, point(pinkyPip)),
    _landmark(
      HandLandmarkType.pinkyDIP,
      Offset.lerp(point(pinkyPip), point(pinkyTip), 0.5)!,
    ),
    _landmark(HandLandmarkType.pinkyTip, point(pinkyTip)),
  ];

  return Hand(
    boundingBox: BoundingBox.ltrb(40, 40, 360, 360),
    score: 1,
    landmarks: landmarks,
    imageWidth: _imageSize.width.toInt(),
    imageHeight: _imageSize.height.toInt(),
    handedness: Handedness.right,
    gesture: gesture,
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
