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

    test('accepts an adjacent vertical gap at the exact minimum', () {
      final detector = CustomGestureDetector();
      final startedAt = DateTime(2026, 7, 18, 10);
      final baseline = _allLongFingersHand();
      final indexMcp = _landmarkOffset(
        baseline,
        HandLandmarkType.indexFingerMCP,
      );
      final handSize = 220.0;
      final minGap =
          handSize *
          HandGestureThresholds.returnToMainMinAdjacentVerticalGapHandSizeRatio;
      final hand = _allLongFingersHand(
        landmarkOverrides: {
          HandLandmarkType.indexFingerPIP: Offset(
            indexMcp.dx,
            indexMcp.dy + minGap,
          ),
        },
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
              now: startedAt.add(
                HandGestureThresholds.returnToMainDownHoldDuration,
              ),
            )
            .isCancelEverything,
        isTrue,
      );
    });

    test('any too-close neighboring pair on any finger cancels the pose', () {
      const chains = HandGestureThresholds.directionFingerChainTypes;
      final baseline = _allLongFingersHand();
      final minGap =
          220.0 *
          HandGestureThresholds.returnToMainMinAdjacentVerticalGapHandSizeRatio;

      for (final chain in chains) {
        for (var pairIndex = 0; pairIndex < 3; pairIndex += 1) {
          final detector = CustomGestureDetector();
          final previous = _landmarkOffset(baseline, chain[pairIndex]);
          final next = _landmarkOffset(baseline, chain[pairIndex + 1]);
          final hand = _allLongFingersHand(
            landmarkOverrides: {
              chain[pairIndex + 1]: Offset(next.dx, previous.dy + minGap - 0.1),
            },
          );
          final startedAt = DateTime(2026, 7, 18, 10);

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
            reason: '${chain[pairIndex].name}→${chain[pairIndex + 1].name}',
          );
        }
      }
    });

    test('a locally reversed pair cancels despite an overall downward tip', () {
      final detector = CustomGestureDetector();
      final startedAt = DateTime(2026, 7, 18, 10);
      final middlePip = _landmarkOffset(
        _allLongFingersHand(),
        HandLandmarkType.middleFingerPIP,
      );
      final hand = _allLongFingersHand(
        landmarkOverrides: {
          HandLandmarkType.middleFingerDIP: Offset(
            middlePip.dx,
            middlePip.dy - 1,
          ),
        },
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
    test('recording path detects punch immediately before its time hold', () {
      final detector = CustomGestureDetector();

      final result = detector.detect(
        hand: _punchHand(),
        imageSize: _imageSize,
        mirrorHorizontally: false,
        requirePunchConfirmation: false,
      );

      expect(result.isPunch, isTrue);
      expect(
        HandGestureThresholds.recordPauseHoldDuration,
        const Duration(seconds: 1),
      );
    });

    test('normal preview confirms a steady punch on exactly frame three', () {
      final detector = CustomGestureDetector();
      final hand = _punchHand();

      for (var frame = 1; frame <= 3; frame += 1) {
        final result = detector.detect(
          hand: hand,
          imageSize: _imageSize,
          mirrorHorizontally: false,
          requirePunchConfirmation: true,
        );

        expect(
          result.isPunch,
          frame == HandGestureThresholds.punchRequiredConsecutiveFrames,
          reason: 'frame $frame',
        );
      }
    });

    test('normal preview allows small hand-center jitter', () {
      final detector = CustomGestureDetector();

      for (final testCase in const [
        (Offset.zero, false),
        (Offset(4, 0), false),
        (Offset(8, 0), true),
      ]) {
        expect(
          detector
              .detect(
                hand: _punchHand(palmOffset: testCase.$1),
                imageSize: _imageSize,
                mirrorHorizontally: false,
                requirePunchConfirmation: true,
              )
              .isPunch,
          testCase.$2,
        );
      }
    });

    test('moving hand restarts three steady punch frames', () {
      final detector = CustomGestureDetector();

      expect(
        detector
            .detect(
              hand: _punchHand(),
              imageSize: _imageSize,
              mirrorHorizontally: false,
              requirePunchConfirmation: true,
            )
            .isPunch,
        isFalse,
      );
      expect(
        detector
            .detect(
              hand: _punchHand(palmOffset: const Offset(20, 0)),
              imageSize: _imageSize,
              mirrorHorizontally: false,
              requirePunchConfirmation: true,
            )
            .isPunch,
        isFalse,
      );

      for (var steadyFrame = 1; steadyFrame <= 3; steadyFrame += 1) {
        expect(
          detector
              .detect(
                hand: _punchHand(palmOffset: const Offset(20, 0)),
                imageSize: _imageSize,
                mirrorHorizontally: false,
                requirePunchConfirmation: true,
              )
              .isPunch,
          steadyFrame == 3,
          reason: 'steady frame $steadyFrame after movement',
        );
      }
    });

    test('a non-punch frame resets normal-preview confirmation', () {
      final detector = CustomGestureDetector();
      final punch = _punchHand();

      for (var frame = 0; frame < 2; frame += 1) {
        expect(
          detector
              .detect(
                hand: punch,
                imageSize: _imageSize,
                mirrorHorizontally: false,
                requirePunchConfirmation: true,
              )
              .isPunch,
          isFalse,
        );
      }

      expect(
        detector
            .detect(
              hand: _punchHand(
                missingTypes: const {
                  HandLandmarkType.thumbTip,
                  HandLandmarkType.indexFingerTip,
                  HandLandmarkType.ringFingerTip,
                  HandLandmarkType.pinkyTip,
                },
              ),
              imageSize: _imageSize,
              mirrorHorizontally: false,
              requirePunchConfirmation: true,
            )
            .isPunch,
        isFalse,
      );

      for (var frame = 1; frame <= 3; frame += 1) {
        expect(
          detector
              .detect(
                hand: punch,
                imageSize: _imageSize,
                mirrorHorizontally: false,
                requirePunchConfirmation: true,
              )
              .isPunch,
          frame == 3,
          reason: 'frame $frame after interruption',
        );
      }
    });

    test('recording mode clears partial normal-preview confirmation', () {
      final detector = CustomGestureDetector();
      final punch = _punchHand();

      for (var frame = 0; frame < 2; frame += 1) {
        expect(
          detector
              .detect(
                hand: punch,
                imageSize: _imageSize,
                mirrorHorizontally: false,
                requirePunchConfirmation: true,
              )
              .isPunch,
          isFalse,
        );
      }

      expect(
        detector
            .detect(
              hand: punch,
              imageSize: _imageSize,
              mirrorHorizontally: false,
              requirePunchConfirmation: false,
            )
            .isPunch,
        isTrue,
      );

      for (var frame = 1; frame <= 3; frame += 1) {
        expect(
          detector
              .detect(
                hand: punch,
                imageSize: _imageSize,
                mirrorHorizontally: false,
                requirePunchConfirmation: true,
              )
              .isPunch,
          frame == 3,
          reason: 'normal-preview frame $frame after recording mode',
        );
      }
    });

    test('clearState resets partial punch confirmation', () {
      final detector = CustomGestureDetector();
      final punch = _punchHand();

      for (var frame = 0; frame < 2; frame += 1) {
        detector.detect(
          hand: punch,
          imageSize: _imageSize,
          mirrorHorizontally: false,
          requirePunchConfirmation: true,
        );
      }

      detector.clearState();

      expect(
        detector
            .detect(
              hand: punch,
              imageSize: _imageSize,
              mirrorHorizontally: false,
              requirePunchConfirmation: true,
            )
            .isPunch,
        isFalse,
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

    test('ignores package gesture type for Punch', () {
      for (final hand in [
        _punchHand(gesture: null),
        _punchHand(
          gesture: const GestureResult(
            type: GestureType.unknown,
            confidence: 0,
          ),
        ),
        _punchHand(
          gesture: const GestureResult(
            type: GestureType.thumbDown,
            confidence: 1,
          ),
        ),
        _punchHand(
          gesture: const GestureResult(
            type: GestureType.victory,
            confidence: 1,
          ),
        ),
      ]) {
        final detector = CustomGestureDetector();
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
      }
    });

    test('ignores package confidence for Punch', () {
      for (final confidence in const [0.0, 0.49, double.nan]) {
        final detector = CustomGestureDetector();
        final result = detector.detect(
          hand: _punchHand(
            gesture: GestureResult(
              type: GestureType.closedFist,
              confidence: confidence,
            ),
          ),
          imageSize: _imageSize,
          mirrorHorizontally: false,
        );

        expect(result.isPunch, isTrue, reason: 'confidence=$confidence');
      }
    });

    test('accepts all 21 visible points inside including point 0', () {
      final detector = CustomGestureDetector();
      final result = detector.detect(
        hand: _punchHand(),
        imageSize: _imageSize,
        mirrorHorizontally: false,
      );

      expect(result.isPunch, isTrue);
    });

    test('keeps the package pose as Closed Fist when only 20 points count', () {
      final detector = CustomGestureDetector();
      final result = detector.detect(
        hand: _punchHand(missingTypes: const {HandLandmarkType.thumbTip}),
        imageSize: _imageSize,
        mirrorHorizontally: false,
      );

      expect(result.isPunch, isFalse);
    });

    test('requires point 0 even when the other 20 points are compact', () {
      final detector = CustomGestureDetector();
      final result = detector.detect(
        hand: _punchHand(missingTypes: const {HandLandmarkType.wrist}),
        imageSize: _imageSize,
        mirrorHorizontally: false,
      );

      expect(result.isPunch, isFalse);
    });

    test('requires point 10 for the circle center', () {
      final detector = CustomGestureDetector();
      final result = detector.detect(
        hand: _punchHand(
          missingTypes: const {HandLandmarkType.middleFingerPIP},
        ),
        imageSize: _imageSize,
        mirrorHorizontally: false,
      );

      expect(result.isPunch, isFalse);
    });

    test('rejects a missing point 9 or point 12 despite center fallback', () {
      for (final missingType in const [
        HandLandmarkType.middleFingerMCP,
        HandLandmarkType.middleFingerTip,
      ]) {
        final detector = CustomGestureDetector();
        final result = detector.detect(
          hand: _punchHand(missingTypes: {missingType}),
          imageSize: _imageSize,
          mirrorHorizontally: false,
        );

        expect(result.isPunch, isFalse, reason: missingType.name);
      }
    });

    test('accepts zero outside points but rejects one outside point', () {
      final detector = CustomGestureDetector();
      const outside = Offset(20, 20);
      final zeroOutside = _punchHand();
      final oneOutside = _punchHand(
        landmarkOverrides: const {HandLandmarkType.thumbTip: outside},
      );

      expect(
        detector
            .detect(
              hand: zeroOutside,
              imageSize: _imageSize,
              mirrorHorizontally: false,
            )
            .isPunch,
        isTrue,
      );
      expect(
        detector
            .detect(
              hand: oneOutside,
              imageSize: _imageSize,
              mirrorHorizontally: false,
            )
            .isPunch,
        isFalse,
      );
    });

    test('old finger-angle rule no longer gates an all-inside punch', () {
      final detector = CustomGestureDetector();

      expect(
        detector
            .detect(
              hand: _punchHand(
                landmarkOverrides: const {
                  HandLandmarkType.indexFingerPIP: Offset(180, 220),
                  HandLandmarkType.indexFingerDIP: Offset(200, 240),
                  HandLandmarkType.indexFingerTip: Offset(220, 260),
                },
              ),
              imageSize: _imageSize,
              mirrorHorizontally: false,
            )
            .isPunch,
        isTrue,
      );
    });

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
  });
}

Offset _landmarkOffset(Hand hand, HandLandmarkType type) {
  final landmark = hand.landmarks.firstWhere(
    (landmark) => landmark.type == type,
  );
  return Offset(landmark.x, landmark.y);
}

Hand _allLongFingersHand({
  List<Offset> fingerVectors = const [
    Offset(0, 90),
    Offset(0, 90),
    Offset(0, 90),
    Offset(0, 90),
  ],
  double score = 1,
  Map<HandLandmarkType, Offset> landmarkOverrides = const {},
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
      final type = chainTypes[fingerIndex][pointIndex];
      landmarks.add(
        _landmark(
          type,
          landmarkOverrides[type] ?? base + vector * (pointIndex / 3),
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
  Offset thumbTip = const Offset(205, 232),
  Set<HandLandmarkType> missingTypes = const {},
  Map<HandLandmarkType, Offset> landmarkOverrides = const {},
  double rotationDegrees = 0,
  bool mirrorPose = false,
  double scale = 1,
  Offset palmOffset = Offset.zero,
  Offset wrist = const Offset(215, 225),
  GestureResult? gesture = const GestureResult(
    type: GestureType.closedFist,
    confidence: 1,
  ),
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
    landmarks.add(
      _landmark(
        type,
        point(landmarkOverrides[type] ?? base),
        visibility: visibility,
      ),
    );
  }

  const thumbCmc = Offset(230, 220);
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
    [Offset(160, 200), Offset(190, 245), Offset(220, 252.5), Offset(245, 255)],
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
  add(HandLandmarkType.thumbCMC, thumbCmc);
  add(HandLandmarkType.thumbMCP, thumbMcp);
  add(HandLandmarkType.thumbIP, thumbIp);
  add(HandLandmarkType.thumbTip, thumbTip);

  for (var fingerIndex = 0; fingerIndex < chainTypes.length; fingerIndex++) {
    final points = openFingerIndexes.contains(fingerIndex)
        ? [
            foldedChains[fingerIndex][0],
            openPips[fingerIndex],
            Offset.lerp(openPips[fingerIndex], openTips[fingerIndex], 0.5)!,
            openTips[fingerIndex],
          ]
        : [...foldedChains[fingerIndex]];
    for (var pointIndex = 0; pointIndex < points.length; pointIndex++) {
      add(chainTypes[fingerIndex][pointIndex], points[pointIndex]);
    }
  }

  return Hand(
    boundingBox: BoundingBox.ltrb(
      40 + palmOffset.dx,
      40 + palmOffset.dy,
      360 + palmOffset.dx,
      360 + palmOffset.dy,
    ),
    score: score,
    landmarks: landmarks,
    imageWidth: _imageSize.width.toInt(),
    imageHeight: _imageSize.height.toInt(),
    handedness: Handedness.right,
    gesture: gesture,
  );
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
