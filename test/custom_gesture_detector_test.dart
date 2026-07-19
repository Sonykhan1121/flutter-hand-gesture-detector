import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gesture_detector/hand_gesture_features/domain/constants/hand_gesture_thresholds.dart';
import 'package:gesture_detector/hand_gesture_features/domain/services/custom_gesture_detector.dart';
import 'package:hand_detection/hand_detection.dart';

const _imageSize = Size(400, 400);

void main() {
  group('CustomGestureDetector return to main position', () {
    test('detects all four long fingers down after a one-second hold', () {
      final detector = CustomGestureDetector();
      final startedAt = DateTime(2026, 7, 18, 10);
      final hand = _allLongFingersHand();

      expect(
        detector
            .detect(
              hand: hand,
              imageSize: _imageSize,
              mirrorHorizontally: false,
              now: startedAt,
            )
            .isCancelEverything,
        isFalse,
      );

      expect(
        detector
            .detect(
              hand: hand,
              imageSize: _imageSize,
              mirrorHorizontally: false,
              now: startedAt.add(const Duration(milliseconds: 999)),
            )
            .isCancelEverything,
        isFalse,
      );

      expect(
        detector
            .detect(
              hand: hand,
              imageSize: _imageSize,
              mirrorHorizontally: false,
              now: startedAt.add(
                HandGestureThresholds.returnToMainDownHoldDuration,
              ),
            )
            .isCancelEverything,
        isTrue,
      );
    });

    test('does not trigger for another static direction', () {
      final detector = CustomGestureDetector();
      final startedAt = DateTime(2026, 7, 18, 10);

      for (final elapsed in const [
        Duration.zero,
        Duration(seconds: 1),
        Duration(seconds: 2),
      ]) {
        final result = detector.detect(
          hand: _allLongFingersHand(
            fingerVectors: const [
              Offset(-90, 0),
              Offset(-90, 0),
              Offset(-90, 0),
              Offset(-90, 0),
            ],
          ),
          imageSize: _imageSize,
          mirrorHorizontally: false,
          now: startedAt.add(elapsed),
        );

        expect(result.isCancelEverything, isFalse);
      }
    });

    test('changing direction resets the one-second hold', () {
      final detector = CustomGestureDetector();
      final startedAt = DateTime(2026, 7, 18, 10);
      final downHand = _allLongFingersHand();

      detector.detect(
        hand: downHand,
        imageSize: _imageSize,
        mirrorHorizontally: false,
        now: startedAt,
      );
      detector.detect(
        hand: _allLongFingersHand(
          fingerVectors: const [
            Offset(0, -90),
            Offset(0, -90),
            Offset(0, -90),
            Offset(0, -90),
          ],
        ),
        imageSize: _imageSize,
        mirrorHorizontally: false,
        now: startedAt.add(const Duration(milliseconds: 600)),
      );

      expect(
        detector
            .detect(
              hand: downHand,
              imageSize: _imageSize,
              mirrorHorizontally: false,
              now: startedAt.add(const Duration(milliseconds: 700)),
            )
            .isCancelEverything,
        isFalse,
      );

      expect(
        detector
            .detect(
              hand: downHand,
              imageSize: _imageSize,
              mirrorHorizontally: false,
              now: startedAt.add(const Duration(milliseconds: 1699)),
            )
            .isCancelEverything,
        isFalse,
      );

      expect(
        detector
            .detect(
              hand: downHand,
              imageSize: _imageSize,
              mirrorHorizontally: false,
              now: startedAt.add(const Duration(milliseconds: 1700)),
            )
            .isCancelEverything,
        isTrue,
      );
    });

    test('invalid hand resets the partial down hold', () {
      final detector = CustomGestureDetector();
      final startedAt = DateTime(2026, 7, 18, 10);
      final hand = _allLongFingersHand();

      detector.detect(
        hand: hand,
        imageSize: _imageSize,
        mirrorHorizontally: false,
        now: startedAt,
      );

      expect(
        detector
            .detect(
              hand: _allLongFingersHand(score: double.nan),
              imageSize: _imageSize,
              mirrorHorizontally: false,
              now: startedAt.add(const Duration(milliseconds: 800)),
            )
            .hasAny,
        isFalse,
      );
      expect(
        detector
            .detect(
              hand: hand,
              imageSize: _imageSize,
              mirrorHorizontally: false,
              now: startedAt.add(const Duration(seconds: 1)),
            )
            .isCancelEverything,
        isFalse,
      );
    });

    test('clearState resets the partial down hold', () {
      final detector = CustomGestureDetector();
      final startedAt = DateTime(2026, 7, 18, 10);
      final hand = _allLongFingersHand();

      detector.detect(
        hand: hand,
        imageSize: _imageSize,
        mirrorHorizontally: false,
        now: startedAt,
      );

      detector.clearState();

      expect(
        detector
            .detect(
              hand: hand,
              imageSize: _imageSize,
              mirrorHorizontally: false,
              now: startedAt.add(const Duration(seconds: 1)),
            )
            .isCancelEverything,
        isFalse,
      );
    });

    test('index-only moving down does not trigger return to main', () {
      final detector = CustomGestureDetector();
      final startedAt = DateTime(2026, 7, 18, 10);
      final hand = _indexOnlyHand(indexTip: const Offset(200, 310));

      expect(
        detector
            .detect(
              hand: hand,
              imageSize: _imageSize,
              mirrorHorizontally: false,
              now: startedAt,
            )
            .isCancelEverything,
        isFalse,
      );

      expect(
        detector
            .detect(
              hand: hand,
              imageSize: _imageSize,
              mirrorHorizontally: false,
              now: startedAt.add(const Duration(seconds: 2)),
            )
            .isCancelEverything,
        isFalse,
      );
    });

    test('three downward fingers are not enough', () {
      final detector = CustomGestureDetector();
      final startedAt = DateTime(2026, 7, 18, 10);
      final hand = _allLongFingersHand(
        fingerVectors: const [
          Offset(0, 90),
          Offset(0, 90),
          Offset(0, 90),
          Offset(90, 0),
        ],
      );

      detector.detect(
        hand: hand,
        imageSize: _imageSize,
        mirrorHorizontally: false,
        now: startedAt,
      );

      expect(
        detector
            .detect(
              hand: hand,
              imageSize: _imageSize,
              mirrorHorizontally: false,
              now: startedAt.add(const Duration(seconds: 2)),
            )
            .isCancelEverything,
        isFalse,
      );
    });

    test('the previous index-circle motion no longer triggers', () {
      final detector = CustomGestureDetector();
      final startedAt = DateTime(2026, 7, 18, 10);
      const oldCirclePoints = [
        Offset(205, 130),
        Offset(202, 135),
        Offset(196, 133),
        Offset(196, 127),
        Offset(202, 125),
      ];

      for (var index = 0; index < oldCirclePoints.length; index++) {
        expect(
          detector
              .detect(
                hand: _indexOnlyHand(indexTip: oldCirclePoints[index]),
                imageSize: _imageSize,
                mirrorHorizontally: false,
                now: startedAt.add(Duration(milliseconds: index * 100)),
              )
              .isCancelEverything,
          isFalse,
        );
      }
    });
  });

  group('CustomGestureDetector punch', () {
    test('detects punch immediately without adding a display hold', () {
      final detector = CustomGestureDetector();

      final result = detector.detect(
        hand: _punchHand(),
        imageSize: _imageSize,
        mirrorHorizontally: false,
      );

      expect(result.isPunch, isTrue);
      expect(
        HandGestureThresholds.recordPauseHoldDuration,
        const Duration(seconds: 1),
      );
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

    test('one extended index pointing down is not punch', () {
      final detector = CustomGestureDetector();

      final result = detector.detect(
        hand: _indexOnlyHand(indexTip: const Offset(200, 310)),
        imageSize: _imageSize,
        mirrorHorizontally: false,
      );

      expect(result.isPunch, isFalse);
    });

    for (final testCase in const [
      (Offset(168, 205), 'MCP'),
      (Offset(168, 242), 'PIP'),
      (Offset(190, 252), 'DIP'),
      (Offset(210, 260), 'tip'),
    ]) {
      test('accepts thumb close to the index ${testCase.$2}', () {
        final detector = CustomGestureDetector();

        final result = detector.detect(
          hand: _punchHand(thumbTip: testCase.$1),
          imageSize: _imageSize,
          mirrorHorizontally: false,
        );

        expect(result.isPunch, isTrue);
      });
    }

    for (final rotation in const [0.0, 90.0, 180.0, 270.0]) {
      test('accepts a punch rotated ${rotation.toInt()} degrees', () {
        final detector = CustomGestureDetector();

        final result = detector.detect(
          hand: _punchHand(rotationDegrees: rotation),
          imageSize: _imageSize,
          mirrorHorizontally: false,
        );

        expect(result.isPunch, isTrue);
      });
    }

    test('accepts a mirrored punch for either preview mirror setting', () {
      final detector = CustomGestureDetector();
      final hand = _punchHand(mirrorPose: true);

      expect(
        detector
            .detect(
              hand: hand,
              imageSize: _imageSize,
              mirrorHorizontally: false,
            )
            .isPunch,
        isTrue,
      );
      expect(
        detector
            .detect(hand: hand, imageSize: _imageSize, mirrorHorizontally: true)
            .isPunch,
        isTrue,
      );
    });

    test('rejects a distant thumb', () {
      final detector = CustomGestureDetector();

      final result = detector.detect(
        hand: _punchHand(thumbTip: const Offset(300, 235)),
        imageSize: _imageSize,
        mirrorHorizontally: false,
      );

      expect(result.isPunch, isFalse);
    });

    test('rejects a missing or unreliable thumb tip', () {
      final detector = CustomGestureDetector();

      expect(
        detector
            .detect(
              hand: _punchHand(includeThumbTip: false),
              imageSize: _imageSize,
              mirrorHorizontally: false,
            )
            .isPunch,
        isFalse,
      );
      expect(
        detector
            .detect(
              hand: _punchHand(lowVisibilityThumbTip: true),
              imageSize: _imageSize,
              mirrorHorizontally: false,
            )
            .isPunch,
        isFalse,
      );
    });

    for (var fingerIndex = 0; fingerIndex < 4; fingerIndex++) {
      test('rejects punch when long finger $fingerIndex is open', () {
        final detector = CustomGestureDetector();

        final result = detector.detect(
          hand: _punchHand(openFingerIndexes: {fingerIndex}),
          imageSize: _imageSize,
          mirrorHorizontally: false,
        );

        expect(result.isPunch, isFalse);
      });
    }

    test('package thumb down with open fingers is not punch', () {
      final detector = CustomGestureDetector();

      final result = detector.detect(
        hand: _punchHand(
          openFingerIndexes: const {0, 1, 2, 3},
          thumbTip: const Offset(300, 235),
          gesture: const GestureResult(
            type: GestureType.thumbDown,
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

    test('rejects a partially folded index that can still be pointing', () {
      final detector = CustomGestureDetector();

      final result = detector.detect(
        hand: _punchHand(fingerTipOverrides: const {0: Offset(186, 276)}),
        imageSize: _imageSize,
        mirrorHorizontally: false,
      );

      expect(result.isPunch, isFalse);
    });

    test('missing an index-chain landmark rejects punch', () {
      final detector = CustomGestureDetector();

      final result = detector.detect(
        hand: _punchHand(missingTypes: const {HandLandmarkType.indexFingerDIP}),
        imageSize: _imageSize,
        mirrorHorizontally: false,
      );

      expect(result.isPunch, isFalse);
    });
  });
}

Hand _allLongFingersHand({
  List<Offset> fingerVectors = const [
    Offset(0, 90),
    Offset(0, 90),
    Offset(0, 90),
    Offset(0, 90),
  ],
  double score = 1,
}) {
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
  const fingerBases = [
    Offset(165, 190),
    Offset(190, 190),
    Offset(215, 190),
    Offset(240, 190),
  ];
  final landmarks = <HandLandmark>[
    _landmark(HandLandmarkType.wrist, const Offset(205, 125)),
    _landmark(HandLandmarkType.thumbMCP, const Offset(165, 165)),
    _landmark(HandLandmarkType.thumbIP, const Offset(145, 175)),
    _landmark(HandLandmarkType.thumbTip, const Offset(130, 185)),
  ];

  for (var fingerIndex = 0; fingerIndex < chainTypes.length; fingerIndex++) {
    final base = fingerBases[fingerIndex];
    final vector = fingerVectors[fingerIndex];

    for (var pointIndex = 0; pointIndex < 4; pointIndex++) {
      landmarks.add(
        _landmark(
          chainTypes[fingerIndex][pointIndex],
          base + vector * (pointIndex / 3),
        ),
      );
    }
  }

  return Hand(
    boundingBox: BoundingBox.ltrb(100, 100, 300, 320),
    score: score,
    landmarks: landmarks,
    imageWidth: _imageSize.width.toInt(),
    imageHeight: _imageSize.height.toInt(),
    handedness: Handedness.right,
  );
}

Hand _indexOnlyHand({required Offset indexTip, double score = 1}) {
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
    _landmark(HandLandmarkType.middleFingerDIP, const Offset(215, 234)),
    _landmark(HandLandmarkType.middleFingerTip, const Offset(213, 229)),
    _landmark(HandLandmarkType.ringFingerMCP, ringMcp),
    _landmark(HandLandmarkType.ringFingerPIP, const Offset(226, 243)),
    _landmark(HandLandmarkType.ringFingerDIP, const Offset(225, 239)),
    _landmark(HandLandmarkType.ringFingerTip, const Offset(223, 234)),
    _landmark(HandLandmarkType.pinkyMCP, pinkyMcp),
    _landmark(HandLandmarkType.pinkyPIP, const Offset(236, 248)),
    _landmark(HandLandmarkType.pinkyDIP, const Offset(235, 244)),
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
  Set<int> openFingerIndexes = const {},
  Map<int, Offset> fingerTipOverrides = const {},
  Offset thumbTip = const Offset(205, 232),
  bool includeThumbTip = true,
  bool lowVisibilityThumbTip = false,
  Set<HandLandmarkType> missingTypes = const {},
  double rotationDegrees = 0,
  bool mirrorPose = false,
  double scale = 1,
  Offset palmOffset = Offset.zero,
  Offset wrist = const Offset(215, 225),
  GestureResult? gesture,
  double score = 1,
}) {
  const basePalmCenter = Offset(204, 220);
  final rotationRadians = rotationDegrees * math.pi / 180;

  Offset point(Offset base) {
    final sourceX = (base.dx - basePalmCenter.dx) * scale;
    final sourceY = (base.dy - basePalmCenter.dy) * scale;
    final rotatedX =
        sourceX * math.cos(rotationRadians) -
        sourceY * math.sin(rotationRadians);
    final rotatedY =
        sourceX * math.sin(rotationRadians) +
        sourceY * math.cos(rotationRadians);

    return Offset(
      basePalmCenter.dx + (mirrorPose ? -rotatedX : rotatedX) + palmOffset.dx,
      basePalmCenter.dy + rotatedY + palmOffset.dy,
    );
  }

  final landmarks = <HandLandmark>[];

  void add(HandLandmarkType type, Offset base, {double visibility = 1}) {
    if (missingTypes.contains(type)) return;
    landmarks.add(_landmark(type, point(base), visibility: visibility));
  }

  const thumbMcp = Offset(230, 230);
  const thumbIp = Offset(210, 238);
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
  const foldedChains = [
    [Offset(160, 200), Offset(160, 245), Offset(182.5, 255), Offset(205, 265)],
    [Offset(190, 200), Offset(190, 245), Offset(210, 252.5), Offset(230, 260)],
    [Offset(220, 200), Offset(220, 245), Offset(200, 252.5), Offset(180, 260)],
    [
      Offset(250, 200),
      Offset(250, 245),
      Offset(227.5, 252.5),
      Offset(205, 260),
    ],
  ];
  const openTips = [
    Offset(160, 90),
    Offset(190, 80),
    Offset(220, 80),
    Offset(250, 90),
  ];
  const openPips = [
    Offset(160, 150),
    Offset(190, 145),
    Offset(220, 145),
    Offset(250, 150),
  ];

  add(HandLandmarkType.wrist, wrist);
  add(HandLandmarkType.thumbMCP, thumbMcp);
  add(HandLandmarkType.thumbIP, thumbIp);
  if (includeThumbTip) {
    add(
      HandLandmarkType.thumbTip,
      thumbTip,
      visibility: lowVisibilityThumbTip ? 0.2 : 1,
    );
  }

  for (var fingerIndex = 0; fingerIndex < chainTypes.length; fingerIndex++) {
    final points = openFingerIndexes.contains(fingerIndex)
        ? [
            foldedChains[fingerIndex][0],
            openPips[fingerIndex],
            Offset.lerp(openPips[fingerIndex], openTips[fingerIndex], 0.5)!,
            openTips[fingerIndex],
          ]
        : [...foldedChains[fingerIndex]];
    final tipOverride = fingerTipOverrides[fingerIndex];
    if (tipOverride != null) points[3] = tipOverride;

    for (var pointIndex = 0; pointIndex < points.length; pointIndex++) {
      add(chainTypes[fingerIndex][pointIndex], points[pointIndex]);
    }
  }

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

HandLandmark _landmark(
  HandLandmarkType type,
  Offset point, {
  double z = 0,
  double visibility = 1,
}) {
  return HandLandmark(
    type: type,
    x: point.dx,
    y: point.dy,
    z: z,
    visibility: visibility,
  );
}
