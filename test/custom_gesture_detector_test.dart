import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gesture_detector/hand_gesture_features/domain/constants/hand_gesture_thresholds.dart';
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

    test('does not detect a circle when index depth drifts too much', () {
      final detector = CustomGestureDetector();
      final points = _circlePoints(center: const Offset(200, 130), radius: 5);

      for (var index = 0; index < points.length; index++) {
        final result = detector.detect(
          hand: _indexOnlyHand(indexTip: points[index], indexTipZ: index * 60),
          imageSize: _imageSize,
          mirrorHorizontally: false,
        );

        expect(result.isCancelEverything, isFalse);
      }
    });

    test('invalid hand resets partial circle history', () {
      final detector = CustomGestureDetector();
      final points = _circlePoints(center: const Offset(200, 130), radius: 5);

      for (final point in points.take(4)) {
        expect(
          detector
              .detect(
                hand: _indexOnlyHand(indexTip: point),
                imageSize: _imageSize,
                mirrorHorizontally: false,
              )
              .isCancelEverything,
          isFalse,
        );
      }

      expect(
        detector
            .detect(
              hand: _indexOnlyHand(indexTip: points.last, score: double.nan),
              imageSize: _imageSize,
              mirrorHorizontally: false,
            )
            .hasAny,
        isFalse,
      );
      expect(
        detector
            .detect(
              hand: _indexOnlyHand(indexTip: points.last),
              imageSize: _imageSize,
              mirrorHorizontally: false,
            )
            .isCancelEverything,
        isFalse,
      );
    });

    test('clearState resets partial circle history', () {
      final detector = CustomGestureDetector();
      final points = _circlePoints(center: const Offset(200, 130), radius: 5);

      for (final point in points.take(4)) {
        expect(
          detector
              .detect(
                hand: _indexOnlyHand(indexTip: point),
                imageSize: _imageSize,
                mirrorHorizontally: false,
              )
              .isCancelEverything,
          isFalse,
        );
      }

      detector.clearState();

      expect(
        detector
            .detect(
              hand: _indexOnlyHand(indexTip: points.last),
              imageSize: _imageSize,
              mirrorHorizontally: false,
            )
            .isCancelEverything,
        isFalse,
      );
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

    test('rejects punch for non-finite hand confidence', () {
      final detector = CustomGestureDetector();

      final result = detector.detect(
        hand: _punchHand(score: double.infinity),
        imageSize: _imageSize,
        mirrorHorizontally: false,
      );

      expect(result.hasAny, isFalse);
    });

    test('does not punch when wrist is outside other landmarks in 2D', () {
      final detector = CustomGestureDetector();

      final result = detector.detect(
        hand: _punchHand(wrist: const Offset(200, 300)),
        imageSize: _imageSize,
        mirrorHorizontally: false,
      );

      expect(result.isPunch, isFalse);
    });

    test('treats package thumb down as punch', () {
      final detector = CustomGestureDetector();

      final result = detector.detect(
        hand: _punchHand(
          fingersCurled: false,
          thumbTucked: false,
          gesture: const GestureResult(
            type: GestureType.thumbDown,
            confidence: 1,
          ),
        ),
        imageSize: _imageSize,
        mirrorHorizontally: false,
      );

      expect(result.isPunch, isTrue);
    });

    test(
      'package thumb down still fails when wrist is outside other landmarks',
      () {
        final detector = CustomGestureDetector();

        final result = detector.detect(
          hand: _punchHand(
            wrist: const Offset(200, 300),
            fingersCurled: false,
            thumbTucked: false,
            gesture: const GestureResult(
              type: GestureType.thumbDown,
              confidence: 1,
            ),
          ),
          imageSize: _imageSize,
          mirrorHorizontally: false,
        );

        expect(result.isPunch, isFalse);
      },
    );

    test('does not punch for low confidence package thumb down', () {
      final detector = CustomGestureDetector();

      final result = detector.detect(
        hand: _punchHand(
          fingersCurled: false,
          thumbTucked: false,
          gesture: const GestureResult(
            type: GestureType.thumbDown,
            confidence:
                HandGestureThresholds.punchGestureMinPackageConfidence - 0.01,
          ),
        ),
        imageSize: _imageSize,
        mirrorHorizontally: false,
      );

      expect(result.isPunch, isFalse);
    });

    test('does not punch for non-finite package thumb down confidence', () {
      final detector = CustomGestureDetector();

      final result = detector.detect(
        hand: _punchHand(
          fingersCurled: false,
          thumbTucked: false,
          gesture: const GestureResult(
            type: GestureType.thumbDown,
            confidence: double.infinity,
          ),
        ),
        imageSize: _imageSize,
        mirrorHorizontally: false,
      );

      expect(result.isPunch, isFalse);
    });

    test('does not punch when visible thumb is open', () {
      final detector = CustomGestureDetector();

      final result = detector.detect(
        hand: _punchHand(
          thumbTucked: false,
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

    test('does not punch when fingers are open', () {
      final detector = CustomGestureDetector();

      final result = detector.detect(
        hand: _punchHand(fingersCurled: false),
        imageSize: _imageSize,
        mirrorHorizontally: false,
      );

      expect(result.isPunch, isFalse);
    });

    test('does not punch when package closed fist has downward fingers', () {
      final detector = CustomGestureDetector();

      final result = detector.detect(
        hand: _downPointingHand(
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

    test('does not punch for ambiguous half-folded pose', () {
      final detector = CustomGestureDetector();

      final result = detector.detect(
        hand: _halfFoldedHand(
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

Hand _indexOnlyHand({
  required Offset indexTip,
  double indexTipZ = 0,
  double score = 1,
}) {
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
    _landmark(HandLandmarkType.indexFingerTip, indexTip, z: indexTipZ),
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
    score: score,
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
  Offset wrist = const Offset(215, 225),
  GestureResult? gesture,
  double score = 1,
}) {
  const basePalmCenter = Offset(204, 220);

  Offset point(Offset base) {
    return Offset(
      basePalmCenter.dx + (base.dx - basePalmCenter.dx) * scale + palmOffset.dx,
      basePalmCenter.dy + (base.dy - basePalmCenter.dy) * scale + palmOffset.dy,
    );
  }

  const thumbMcp = Offset(230, 230);
  const thumbIp = Offset(210, 238);
  final thumbTip = thumbTucked
      ? const Offset(205, 232)
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
    score: score,
    landmarks: landmarks,
    imageWidth: _imageSize.width.toInt(),
    imageHeight: _imageSize.height.toInt(),
    handedness: Handedness.right,
    gesture: gesture,
  );
}

Hand _downPointingHand({GestureResult? gesture}) {
  return _handFromLongFingerChains(
    chains: [
      _straightChain(const Offset(160, 135), const Offset(0, 115)),
      _straightChain(const Offset(190, 135), const Offset(0, 115)),
      _straightChain(const Offset(220, 135), const Offset(0, 115)),
      _straightChain(const Offset(250, 135), const Offset(0, 115)),
    ],
    gesture: gesture,
  );
}

Hand _halfFoldedHand({GestureResult? gesture}) {
  return _handFromLongFingerChains(
    chains: [
      _foldedChain(const Offset(160, 180), const Offset(45, 70)),
      _foldedChain(const Offset(190, 180), const Offset(40, 70)),
      _straightChain(const Offset(220, 180), const Offset(0, 95)),
      _straightChain(const Offset(250, 180), const Offset(0, 95)),
    ],
    gesture: gesture,
  );
}

Hand _handFromLongFingerChains({
  required List<List<Offset>> chains,
  GestureResult? gesture,
}) {
  final landmarks = <HandLandmark>[
    _landmark(HandLandmarkType.wrist, const Offset(200, 300)),
    _landmark(HandLandmarkType.thumbMCP, const Offset(230, 210)),
    _landmark(HandLandmarkType.thumbIP, const Offset(212, 222)),
    _landmark(HandLandmarkType.thumbTip, const Offset(202, 216)),
  ];

  const chainTypes = [
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

  for (var fingerIndex = 0; fingerIndex < chainTypes.length; fingerIndex++) {
    for (
      var pointIndex = 0;
      pointIndex < chainTypes[fingerIndex].length;
      pointIndex++
    ) {
      landmarks.add(
        _landmark(
          chainTypes[fingerIndex][pointIndex],
          chains[fingerIndex][pointIndex],
        ),
      );
    }
  }

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

List<Offset> _straightChain(Offset base, Offset vector) {
  return List.generate(
    4,
    (pointIndex) => Offset(
      base.dx + vector.dx * pointIndex / 3,
      base.dy + vector.dy * pointIndex / 3,
    ),
  );
}

List<Offset> _foldedChain(Offset base, Offset vector) {
  final tip = base + vector;
  final vectorLength = vector.distance;
  final bendOffset = vectorLength == 0
      ? Offset.zero
      : Offset(-vector.dy / vectorLength, vector.dx / vectorLength) * 35;
  final pip = Offset.lerp(base, tip, 0.5)! + bendOffset;
  final dip = Offset.lerp(pip, tip, 0.5)!;

  return [base, pip, dip, tip];
}

HandLandmark _landmark(HandLandmarkType type, Offset point, {double z = 0}) {
  return HandLandmark(
    type: type,
    x: point.dx,
    y: point.dy,
    z: z,
    visibility: 1,
  );
}
