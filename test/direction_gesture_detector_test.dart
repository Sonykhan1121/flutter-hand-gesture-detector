import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gesture_detector/hand_gesture_features/domain/enums/hand_move_direction.dart';
import 'package:gesture_detector/hand_gesture_features/domain/services/direction_gesture_detector.dart';
import 'package:hand_detection/hand_detection.dart';

const _imageSize = Size(400, 400);

const _fingerChains = [
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

enum _VisibleHandSide { none, palm, back }

void main() {
  group('DirectionGestureDetector finger chains', () {
    late DirectionGestureDetector detector;

    setUp(() {
      detector = DirectionGestureDetector();
    });

    test('returns left when at least three finger chains point left', () {
      final hand = _handWithFingerChainVectors([
        const Offset(-90, 0),
        const Offset(-90, 0),
        const Offset(-90, 0),
        const Offset(90, 0),
      ]);

      expect(_detect(detector, hand), HandMoveDirection.left);
    });

    test('returns right when at least three finger chains point right', () {
      final hand = _handWithFingerChainVectors([
        const Offset(90, 0),
        const Offset(90, 0),
        const Offset(90, 0),
        const Offset(-90, 0),
      ]);

      expect(_detect(detector, hand), HandMoveDirection.right);
    });

    test(
      'returns up when at least three finger chains point up with back side visible',
      () {
        final hand = _handWithFingerChainVectors([
          const Offset(0, -90),
          const Offset(0, -90),
          const Offset(0, -90),
          const Offset(0, 90),
        ], visibleHandSide: _VisibleHandSide.back);

        expect(_detect(detector, hand), HandMoveDirection.up);
      },
    );

    test('returns none when up-pointing chains show palm side', () {
      final hand = _handWithFingerChainVectors([
        const Offset(0, -90),
        const Offset(0, -90),
        const Offset(0, -90),
        const Offset(0, -90),
      ], visibleHandSide: _VisibleHandSide.palm);

      expect(_detect(detector, hand), HandMoveDirection.none);
    });

    test('returns down when at least three finger chains point down', () {
      final hand = _handWithFingerChainVectors([
        const Offset(0, 90),
        const Offset(0, 90),
        const Offset(0, 90),
        const Offset(0, -90),
      ]);

      expect(_detect(detector, hand), HandMoveDirection.down);
    });

    test(
      'returns down when package says closed fist but fingers point down',
      () {
        final hand = _handWithFingerChainVectors(
          [
            const Offset(0, 90),
            const Offset(0, 90),
            const Offset(0, 90),
            const Offset(0, 90),
          ],
          gesture: const GestureResult(
            type: GestureType.closedFist,
            confidence: 1,
          ),
        );

        expect(_detect(detector, hand), HandMoveDirection.down);
      },
    );

    test('flips left and right when coordinates are mirrored', () {
      final hand = _handWithFingerChainVectors([
        const Offset(-90, 0),
        const Offset(-90, 0),
        const Offset(-90, 0),
        const Offset(-90, 0),
      ]);

      expect(
        _detect(detector, hand, mirrorHorizontally: true),
        HandMoveDirection.right,
      );
    });

    test('mirroring does not flip up or down', () {
      final hand = _handWithFingerChainVectors(
        [
          const Offset(20, -90),
          const Offset(20, -90),
          const Offset(20, -90),
          const Offset(20, -90),
        ],
        visibleHandSide: _VisibleHandSide.back,
        mirrorHorizontally: true,
      );

      expect(
        _detect(detector, hand, mirrorHorizontally: true),
        HandMoveDirection.up,
      );
    });

    test('returns right when horizontal movement has small upward drift', () {
      final hand = _handWithFingerChainVectors([
        const Offset(90, -20),
        const Offset(90, -20),
        const Offset(90, -20),
        const Offset(90, -20),
      ]);

      expect(_detect(detector, hand), HandMoveDirection.right);
    });

    test(
      'returns right when horizontal movement has moderate upward drift',
      () {
        final hand = _handWithFingerChainVectors([
          const Offset(90, -78),
          const Offset(90, -78),
          const Offset(90, -78),
          const Offset(90, -78),
        ]);

        expect(_detect(detector, hand), HandMoveDirection.right);
      },
    );

    test('returns up when vertical movement has small rightward drift', () {
      final hand = _handWithFingerChainVectors([
        const Offset(20, -90),
        const Offset(20, -90),
        const Offset(20, -90),
        const Offset(20, -90),
      ], visibleHandSide: _VisibleHandSide.back);

      expect(_detect(detector, hand), HandMoveDirection.up);
    });

    test('returns right for bottom-left to top-right diagonal movement', () {
      final hand = _handWithFingerChainVectors([
        const Offset(90, -84),
        const Offset(90, -84),
        const Offset(90, -84),
        const Offset(90, -84),
      ]);

      expect(_detect(detector, hand), HandMoveDirection.right);
    });

    test(
      'returns right for narrow bottom-left to top-right diagonal movement',
      () {
        final hand = _handWithFingerChainVectors([
          const Offset(25, -90),
          const Offset(25, -90),
          const Offset(25, -90),
          const Offset(25, -90),
        ]);

        expect(_detect(detector, hand), HandMoveDirection.right);
      },
    );

    test('returns left for bottom-right to top-left diagonal movement', () {
      final hand = _handWithFingerChainVectors([
        const Offset(-50, -90),
        const Offset(-50, -90),
        const Offset(-50, -90),
        const Offset(-50, -90),
      ]);

      expect(_detect(detector, hand), HandMoveDirection.left);
    });

    test(
      'returns right or down for diagonal chains with stronger vertical movement',
      () {
        final rightHand = _handWithFingerChainVectors([
          const Offset(50, -90),
          const Offset(50, -90),
          const Offset(50, -90),
          const Offset(50, -90),
        ]);
        final downHand = _handWithFingerChainVectors([
          const Offset(-50, 90),
          const Offset(-50, 90),
          const Offset(-50, 90),
          const Offset(-50, 90),
        ]);

        expect(_detect(detector, rightHand), HandMoveDirection.right);
        expect(_detect(detector, downHand), HandMoveDirection.down);
      },
    );

    test(
      'returns left or right for diagonal chains with stronger horizontal movement',
      () {
        final rightHand = _handWithFingerChainVectors([
          const Offset(90, -50),
          const Offset(90, -50),
          const Offset(90, -50),
          const Offset(90, -50),
        ]);
        final leftHand = _handWithFingerChainVectors([
          const Offset(-90, 50),
          const Offset(-90, 50),
          const Offset(-90, 50),
          const Offset(-90, 50),
        ]);

        expect(_detect(detector, rightHand), HandMoveDirection.right);
        expect(_detect(detector, leftHand), HandMoveDirection.left);
      },
    );

    test('mostly horizontal chains do not return up or down', () {
      final hand = _handWithFingerChainVectors([
        const Offset(90, 8),
        const Offset(90, 8),
        const Offset(90, 8),
        const Offset(90, 8),
      ]);

      expect(
        _detect(detector, hand),
        isNot(anyOf(HandMoveDirection.up, HandMoveDirection.down)),
      );
    });

    test('mostly vertical chains do not return left or right', () {
      final hand = _handWithFingerChainVectors([
        const Offset(8, -90),
        const Offset(8, -90),
        const Offset(8, -90),
        const Offset(8, -90),
      ]);

      expect(
        _detect(detector, hand),
        isNot(anyOf(HandMoveDirection.left, HandMoveDirection.right)),
      );
    });

    test('returns none when finger chains do not have enough movement', () {
      final hand = _handWithFingerChainVectors([
        const Offset(6, 6),
        const Offset(6, 6),
        const Offset(6, 6),
        const Offset(6, 6),
      ]);

      expect(_detect(detector, hand), HandMoveDirection.none);
    });

    test('returns none when fewer than three finger chains agree', () {
      final hand = _handWithFingerChainVectors([
        const Offset(90, 0),
        const Offset(90, 0),
        const Offset(-90, 0),
        const Offset(-90, 0),
      ]);

      expect(_detect(detector, hand), HandMoveDirection.none);
    });

    test('returns none when folded finger chains point up', () {
      final hand = _handWithFingerChainVectors(
        [
          const Offset(0, -90),
          const Offset(0, -90),
          const Offset(0, -90),
          const Offset(0, -90),
        ],
        foldedFingerIndexes: {0, 1, 2, 3},
      );

      expect(_detect(detector, hand), HandMoveDirection.none);
    });

    test('returns none when folded finger chains point down', () {
      final hand = _handWithFingerChainVectors(
        [
          const Offset(0, 90),
          const Offset(0, 90),
          const Offset(0, 90),
          const Offset(0, 90),
        ],
        foldedFingerIndexes: {0, 1, 2, 3},
      );

      expect(_detect(detector, hand), HandMoveDirection.none);
    });

    test('returns none for ambiguous half-folded downward pose', () {
      final hand = _handWithFingerChainVectors(
        [
          const Offset(0, 90),
          const Offset(0, 90),
          const Offset(0, 90),
          const Offset(0, 90),
        ],
        foldedFingerIndexes: {0, 1},
        gesture: const GestureResult(
          type: GestureType.closedFist,
          confidence: 1,
        ),
      );

      expect(_detect(detector, hand), HandMoveDirection.none);
    });

    test('returns none when finger chains move mostly through depth', () {
      final hand = _handWithFingerChainVectors(
        [
          const Offset(20, 0),
          const Offset(20, 0),
          const Offset(20, 0),
          const Offset(20, 0),
        ],
        depthVectors: const [220, 220, 220, 220],
      );

      expect(_detect(detector, hand), HandMoveDirection.none);
    });

    test('returns none for up with only the 16 finger-chain points', () {
      final upHand = _handWithFingerChainVectors([
        const Offset(0, -90),
        const Offset(0, -90),
        const Offset(0, -90),
        const Offset(0, -90),
      ]);
      expect(_detect(detector, upHand), HandMoveDirection.none);
    });

    test('returns down with only the 16 finger-chain points', () {
      final downHand = _handWithFingerChainVectors([
        const Offset(0, 90),
        const Offset(0, 90),
        const Offset(0, 90),
        const Offset(0, 90),
      ]);

      expect(_detect(detector, downHand), HandMoveDirection.down);
    });

    test('returns none when any finger-chain point is missing', () {
      final hand = _handWithFingerChainVectors(
        [
          const Offset(-90, 0),
          const Offset(-90, 0),
          const Offset(-90, 0),
          const Offset(-90, 0),
        ],
        missingTypes: {HandLandmarkType.indexFingerDIP},
      );

      expect(_detect(detector, hand), HandMoveDirection.none);
    });

    test('returns none when any finger-chain point has low visibility', () {
      final hand = _handWithFingerChainVectors(
        [
          const Offset(90, 0),
          const Offset(90, 0),
          const Offset(90, 0),
          const Offset(90, 0),
        ],
        lowVisibilityTypes: {HandLandmarkType.pinkyTip},
      );

      expect(_detect(detector, hand), HandMoveDirection.none);
    });
  });

  group('DirectionGestureDetector fingertip wiggle moving down', () {
    late DirectionGestureDetector detector;

    setUp(() {
      detector = DirectionGestureDetector();
    });

    test('starts from small fingertip position without emitting', () {
      expect(_detect(detector, _handWithWiggleTips()), HandMoveDirection.none);
    });

    test('emits down after repeated small up and down fingertip motion', () {
      expect(_detect(detector, _handWithWiggleTips()), HandMoveDirection.none);
      expect(
        _detect(detector, _handWithWiggleTips(movingTipYOffset: -8)),
        HandMoveDirection.none,
      );
      expect(
        _detect(detector, _handWithWiggleTips(movingTipYOffset: 8)),
        HandMoveDirection.none,
      );
      expect(
        _detect(detector, _handWithWiggleTips(movingTipYOffset: -8)),
        HandMoveDirection.down,
      );
      expect(detector.debugSummary, contains('FIRED'));
    });

    test('emits down when the small shake starts downward', () {
      expect(_detect(detector, _handWithWiggleTips()), HandMoveDirection.none);
      expect(
        _detect(detector, _handWithWiggleTips(movingTipYOffset: 8)),
        HandMoveDirection.none,
      );
      expect(
        _detect(detector, _handWithWiggleTips(movingTipYOffset: -8)),
        HandMoveDirection.none,
      );
      expect(
        _detect(detector, _handWithWiggleTips(movingTipYOffset: 8)),
        HandMoveDirection.down,
      );
    });

    test(
      'emits down even when old left path is detected between wiggle frames',
      () {
        expect(
          _detect(detector, _handWithLeftFingerChains(tipYOffset: 0)),
          HandMoveDirection.left,
        );
        expect(
          _detect(detector, _handWithLeftFingerChains(tipYOffset: -8)),
          HandMoveDirection.left,
        );
        expect(
          _detect(detector, _handWithLeftFingerChains(tipYOffset: 8)),
          HandMoveDirection.left,
        );
        expect(
          _detect(detector, _handWithLeftFingerChains(tipYOffset: -8)),
          HandMoveDirection.down,
        );
        expect(detector.debugSummary, contains('FIRED'));
      },
    );

    test('does not emit when only two fingertips move', () {
      expect(_detect(detector, _handWithWiggleTips()), HandMoveDirection.none);
      expect(
        _detect(
          detector,
          _handWithWiggleTips(
            movingTipYOffset: -8,
            movingFingerIndexes: {0, 1},
          ),
        ),
        HandMoveDirection.none,
      );
      expect(
        _detect(
          detector,
          _handWithWiggleTips(movingTipYOffset: 8, movingFingerIndexes: {0, 1}),
        ),
        HandMoveDirection.none,
      );
      expect(
        _detect(
          detector,
          _handWithWiggleTips(
            movingTipYOffset: -8,
            movingFingerIndexes: {0, 1},
          ),
        ),
        HandMoveDirection.none,
      );
    });

    test('does not emit for tiny camera noise', () {
      expect(_detect(detector, _handWithWiggleTips()), HandMoveDirection.none);
      for (final offset in const [-1.0, 1.0, -1.0, 1.0]) {
        expect(
          _detect(detector, _handWithWiggleTips(movingTipYOffset: offset)),
          HandMoveDirection.none,
        );
      }
    });

    test(
      'does not emit when the small motion has too much horizontal drift',
      () {
        expect(
          _detect(detector, _handWithWiggleTips()),
          HandMoveDirection.none,
        );
        expect(
          _detect(
            detector,
            _handWithWiggleTips(movingTipXOffset: 40, movingTipYOffset: -8),
          ),
          HandMoveDirection.none,
        );
        expect(
          _detect(
            detector,
            _handWithWiggleTips(movingTipXOffset: -40, movingTipYOffset: 8),
          ),
          HandMoveDirection.none,
        );
        expect(
          _detect(
            detector,
            _handWithWiggleTips(movingTipXOffset: 40, movingTipYOffset: -8),
          ),
          HandMoveDirection.none,
        );
      },
    );

    test('does not emit from one-way fingertip movement without shaking', () {
      expect(_detect(detector, _handWithWiggleTips()), HandMoveDirection.none);
      for (final offset in const [6.0, 12.0, 18.0, 24.0]) {
        expect(
          _detect(detector, _handWithWiggleTips(movingTipYOffset: offset)),
          HandMoveDirection.none,
        );
      }
    });

    test('does not emit with low-visibility fingertips', () {
      expect(_detect(detector, _handWithWiggleTips()), HandMoveDirection.none);
      expect(
        _detect(
          detector,
          _handWithWiggleTips(
            movingTipYOffset: -8,
            lowVisibilityTypes: {
              HandLandmarkType.ringFingerTip,
              HandLandmarkType.pinkyTip,
            },
          ),
        ),
        HandMoveDirection.none,
      );
      expect(
        _detect(
          detector,
          _handWithWiggleTips(
            movingTipYOffset: 8,
            lowVisibilityTypes: {
              HandLandmarkType.ringFingerTip,
              HandLandmarkType.pinkyTip,
            },
          ),
        ),
        HandMoveDirection.none,
      );
      expect(detector.debugSummary, contains('low visibility tips=2/4'));
    });

    test('clearState allows a fresh fingertip wiggle sequence', () {
      expect(_detect(detector, _handWithWiggleTips()), HandMoveDirection.none);
      expect(
        _detect(detector, _handWithWiggleTips(movingTipYOffset: -8)),
        HandMoveDirection.none,
      );
      expect(
        _detect(detector, _handWithWiggleTips(movingTipYOffset: 8)),
        HandMoveDirection.none,
      );
      expect(
        _detect(detector, _handWithWiggleTips(movingTipYOffset: -8)),
        HandMoveDirection.down,
      );

      detector.clearState();

      expect(_detect(detector, _handWithWiggleTips()), HandMoveDirection.none);
      expect(
        _detect(detector, _handWithWiggleTips(movingTipYOffset: 8)),
        HandMoveDirection.none,
      );
      expect(
        _detect(detector, _handWithWiggleTips(movingTipYOffset: -8)),
        HandMoveDirection.none,
      );
      expect(
        _detect(detector, _handWithWiggleTips(movingTipYOffset: 8)),
        HandMoveDirection.down,
      );
    });
  });
}

HandMoveDirection _detect(
  DirectionGestureDetector detector,
  Hand hand, {
  bool mirrorHorizontally = false,
}) {
  return detector.detect(
    hand: hand,
    imageSize: _imageSize,
    mirrorHorizontally: mirrorHorizontally,
  );
}

Hand _handWithFingerChainVectors(
  List<Offset> vectors, {
  List<double>? depthVectors,
  Set<HandLandmarkType> missingTypes = const {},
  Set<HandLandmarkType> lowVisibilityTypes = const {},
  Set<int> foldedFingerIndexes = const {},
  _VisibleHandSide visibleHandSide = _VisibleHandSide.none,
  bool mirrorHorizontally = false,
  GestureResult? gesture,
}) {
  final landmarks = <HandLandmark>[];
  final bases = [
    const Offset(220, 140),
    const Offset(220, 170),
    const Offset(220, 200),
    const Offset(220, 230),
  ];

  for (var fingerIndex = 0; fingerIndex < _fingerChains.length; fingerIndex++) {
    final chainTypes = _fingerChains[fingerIndex];
    final base = bases[fingerIndex];
    final vector = vectors[fingerIndex];
    final depthVector = depthVectors == null ? 0.0 : depthVectors[fingerIndex];
    final points =
        foldedFingerIndexes.contains(fingerIndex)
            ? _foldedChainPoints(base, vector)
            : _straightChainPoints(base, vector);

    for (var pointIndex = 0; pointIndex < chainTypes.length; pointIndex++) {
      final type = chainTypes[pointIndex];
      if (missingTypes.contains(type)) continue;

      final point = points[pointIndex];

      landmarks.add(
        HandLandmark(
          type: type,
          x: point.dx,
          y: point.dy,
          z: depthVector * pointIndex / 3,
          visibility: lowVisibilityTypes.contains(type) ? 0.2 : 1,
        ),
      );
    }
  }

  _addVisibleHandSideLandmarks(
    landmarks,
    visibleHandSide: visibleHandSide,
    mirrorHorizontally: mirrorHorizontally,
    missingTypes: missingTypes,
    lowVisibilityTypes: lowVisibilityTypes,
  );

  return Hand(
    boundingBox: BoundingBox.ltrb(0, 0, _imageSize.width, _imageSize.height),
    score: 1,
    landmarks: landmarks,
    imageWidth: _imageSize.width.toInt(),
    imageHeight: _imageSize.height.toInt(),
    handedness: Handedness.right,
    gesture: gesture,
  );
}

Hand _handWithLeftFingerChains({required double tipYOffset}) {
  return _handWithFingerChainVectors([
    Offset(-90, tipYOffset),
    Offset(-90, tipYOffset),
    Offset(-90, tipYOffset),
    Offset(-90, tipYOffset),
  ]);
}

Hand _handWithWiggleTips({
  double movingTipXOffset = 0,
  double movingTipYOffset = 0,
  Set<int> movingFingerIndexes = const {0, 1, 2, 3},
  Set<HandLandmarkType> lowVisibilityTypes = const {},
  GestureResult? gesture,
}) {
  final landmarks = <HandLandmark>[];
  final bases = [
    const Offset(135, 210),
    const Offset(175, 200),
    const Offset(215, 205),
    const Offset(255, 220),
  ];
  final pipOffsets = [
    const Offset(4, -44),
    const Offset(0, -48),
    const Offset(0, -45),
    const Offset(-3, -40),
  ];
  final dipOffsets = [
    const Offset(22, -44),
    const Offset(18, -47),
    const Offset(17, -44),
    const Offset(13, -39),
  ];
  final tipOffsets = [
    const Offset(40, -38),
    const Offset(36, -40),
    const Offset(34, -38),
    const Offset(28, -34),
  ];

  void addLandmark(HandLandmarkType type, Offset point) {
    landmarks.add(
      HandLandmark(
        type: type,
        x: point.dx,
        y: point.dy,
        z: 0,
        visibility: lowVisibilityTypes.contains(type) ? 0.2 : 1,
      ),
    );
  }

  addLandmark(HandLandmarkType.wrist, const Offset(195, 315));
  addLandmark(HandLandmarkType.thumbTip, const Offset(110, 235));

  for (var fingerIndex = 0; fingerIndex < _fingerChains.length; fingerIndex++) {
    final base = bases[fingerIndex];
    final movingOffset =
        movingFingerIndexes.contains(fingerIndex)
            ? Offset(movingTipXOffset, movingTipYOffset)
            : Offset.zero;
    final points = [
      base,
      base + pipOffsets[fingerIndex],
      base + dipOffsets[fingerIndex],
      base + tipOffsets[fingerIndex] + movingOffset,
    ];

    for (
      var pointIndex = 0;
      pointIndex < _fingerChains[fingerIndex].length;
      pointIndex++
    ) {
      addLandmark(_fingerChains[fingerIndex][pointIndex], points[pointIndex]);
    }
  }

  return Hand(
    boundingBox: BoundingBox.ltrb(0, 0, _imageSize.width, _imageSize.height),
    score: 1,
    landmarks: landmarks,
    imageWidth: _imageSize.width.toInt(),
    imageHeight: _imageSize.height.toInt(),
    handedness: Handedness.right,
    gesture: gesture,
  );
}

void _addVisibleHandSideLandmarks(
  List<HandLandmark> landmarks, {
  required _VisibleHandSide visibleHandSide,
  required bool mirrorHorizontally,
  required Set<HandLandmarkType> missingTypes,
  required Set<HandLandmarkType> lowVisibilityTypes,
}) {
  if (visibleHandSide == _VisibleHandSide.none) return;

  final expectedSide = mirrorHorizontally ? -1.0 : 1.0;
  final rawSide =
      visibleHandSide == _VisibleHandSide.back ? -expectedSide : expectedSide;
  final wrist = rawSide < 0 ? const Offset(300, 270) : const Offset(140, 270);
  final thumbTip =
      rawSide < 0 ? const Offset(260, 180) : const Offset(180, 180);

  void addLandmark(HandLandmarkType type, Offset point) {
    if (missingTypes.contains(type)) return;

    landmarks.add(
      HandLandmark(
        type: type,
        x: point.dx,
        y: point.dy,
        z: 0,
        visibility: lowVisibilityTypes.contains(type) ? 0.2 : 1,
      ),
    );
  }

  addLandmark(HandLandmarkType.wrist, wrist);
  addLandmark(HandLandmarkType.thumbTip, thumbTip);
}

List<Offset> _straightChainPoints(Offset base, Offset vector) {
  return List.generate(
    4,
    (pointIndex) => Offset(
      base.dx + vector.dx * pointIndex / 3,
      base.dy + vector.dy * pointIndex / 3,
    ),
  );
}

List<Offset> _foldedChainPoints(Offset base, Offset vector) {
  final tip = base + vector;
  final vectorLength = vector.distance;
  final bendOffset =
      vectorLength == 0
          ? Offset.zero
          : Offset(-vector.dy / vectorLength, vector.dx / vectorLength) * 45;
  final pip = Offset.lerp(base, tip, 0.5)! + bendOffset;
  final dip = Offset.lerp(pip, tip, 0.5)!;

  return [base, pip, dip, tip];
}
