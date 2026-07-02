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

void main() {
  group('DirectionGestureDetector finger chains', () {
    const detector = DirectionGestureDetector();

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

    test('returns up when at least three finger chains point up', () {
      final hand = _handWithFingerChainVectors([
        const Offset(0, -90),
        const Offset(0, -90),
        const Offset(0, -90),
        const Offset(0, 90),
      ]);

      expect(_detect(detector, hand), HandMoveDirection.up);
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
      final hand = _handWithFingerChainVectors([
        const Offset(50, -90),
        const Offset(50, -90),
        const Offset(50, -90),
        const Offset(50, -90),
      ]);

      expect(
        _detect(detector, hand, mirrorHorizontally: true),
        HandMoveDirection.up,
      );
    });

    test(
      'returns up or down for diagonal chains with stronger vertical movement',
      () {
        final upHand = _handWithFingerChainVectors([
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

        expect(_detect(detector, upHand), HandMoveDirection.up);
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

    test('returns up or down with only the 16 finger-chain points', () {
      final upHand = _handWithFingerChainVectors([
        const Offset(0, -90),
        const Offset(0, -90),
        const Offset(0, -90),
        const Offset(0, -90),
      ]);
      final downHand = _handWithFingerChainVectors([
        const Offset(0, 90),
        const Offset(0, 90),
        const Offset(0, 90),
        const Offset(0, 90),
      ]);

      expect(_detect(detector, upHand), HandMoveDirection.up);
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
  Set<HandLandmarkType> missingTypes = const {},
  Set<HandLandmarkType> lowVisibilityTypes = const {},
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

    for (var pointIndex = 0; pointIndex < chainTypes.length; pointIndex++) {
      final type = chainTypes[pointIndex];
      if (missingTypes.contains(type)) continue;

      final point = Offset(
        base.dx + vector.dx * pointIndex / 3,
        base.dy + vector.dy * pointIndex / 3,
      );

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
  }

  return Hand(
    boundingBox: BoundingBox.ltrb(0, 0, _imageSize.width, _imageSize.height),
    score: 1,
    landmarks: landmarks,
    imageWidth: _imageSize.width.toInt(),
    imageHeight: _imageSize.height.toInt(),
    handedness: Handedness.right,
  );
}
