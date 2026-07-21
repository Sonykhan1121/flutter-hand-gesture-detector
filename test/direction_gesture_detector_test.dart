import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gesture_detector/hand_gesture_features/domain/constants/hand_gesture_thresholds.dart';
import 'package:gesture_detector/hand_gesture_features/domain/enums/hand_move_direction.dart';
import 'package:gesture_detector/hand_gesture_features/domain/enums/zoom_direction.dart';
import 'package:gesture_detector/hand_gesture_features/domain/services/direction_gesture_detector.dart';
import 'package:gesture_detector/hand_gesture_features/domain/services/zoom_gesture_detector.dart';
import 'package:hand_detection/hand_detection.dart';

const _imageSize = Size(400, 400);
const _indexBase = Offset(200, 205);
const _verticalUpZoomConflictLandmarks = <HandLandmarkType, Offset>{
  HandLandmarkType.wrist: Offset(0, 285),
  HandLandmarkType.thumbMCP: Offset(200, 220),
  HandLandmarkType.thumbIP: Offset(230, 220),
  HandLandmarkType.thumbTip: Offset(260, 220),
};

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
  group('DirectionGestureDetector static sectors', () {
    late DirectionGestureDetector detector;

    setUp(() {
      detector = DirectionGestureDetector();
    });

    for (final testCase in const [
      (Offset(-90, 0), HandMoveDirection.left, 'left'),
      (Offset(0, -90), HandMoveDirection.up, 'up'),
      (Offset(90, 0), HandMoveDirection.right, 'right'),
      (Offset(0, 90), HandMoveDirection.down, 'down'),
    ]) {
      test('points ${testCase.$3} for the cardinal vector', () {
        final hand = _pointingHand(indexVector: testCase.$1);
        final result = switch (testCase.$2) {
          HandMoveDirection.left => _confirmMovingLeft(detector, hand),
          HandMoveDirection.right => _confirmMovingRight(detector, hand),
          HandMoveDirection.down => _confirmMovingDown(detector, hand),
          _ => _confirmMovingUp(detector, hand),
        };
        expect(result, testCase.$2);
      });
    }

    for (final testCase in const [
      (Offset(-90, -60), HandMoveDirection.left, 'upper-left in region 1'),
      (Offset(-90, 60), HandMoveDirection.left, 'lower-left in region 1'),
      (Offset(-40, -90), HandMoveDirection.up, 'upper-left in up range'),
      (
        Offset(60, -90),
        HandMoveDirection.right,
        'upper-right inside the wider right sector',
      ),
      (Offset(90, -60), HandMoveDirection.right, 'upper-right in region 3'),
      (Offset(90, 60), HandMoveDirection.right, 'lower-right in region 3'),
      (Offset(-40, 90), HandMoveDirection.down, 'lower-left in down range'),
      (Offset(40, 90), HandMoveDirection.down, 'lower-right in down range'),
    ]) {
      test('maps ${testCase.$3}', () {
        final hand = _pointingHand(indexVector: testCase.$1);
        final result = switch (testCase.$2) {
          HandMoveDirection.left => _confirmMovingLeft(detector, hand),
          HandMoveDirection.right => _confirmMovingRight(detector, hand),
          HandMoveDirection.down => _confirmMovingDown(detector, hand),
          _ => _confirmMovingUp(detector, hand),
        };
        expect(result, testCase.$2);
      });
    }

    test('favors a horizontal sector for an initial exact diagonal', () {
      expect(
        _confirmMovingRight(
          detector,
          _pointingHand(indexVector: const Offset(90, -90)),
        ),
        HandMoveDirection.right,
      );
    });

    test('mirroring swaps left and right', () {
      final hand = _pointingHand(indexVector: const Offset(-90, 0));

      expect(
        _confirmMovingRight(detector, hand, mirrorHorizontally: true),
        HandMoveDirection.right,
      );
    });

    test('mirroring does not swap up or down', () {
      expect(
        _confirmMovingUp(
          detector,
          _pointingHand(indexVector: const Offset(20, -90)),
          mirrorHorizontally: true,
        ),
        HandMoveDirection.up,
      );

      detector.clearState();

      expect(
        _confirmMovingDown(
          detector,
          _pointingHand(indexVector: const Offset(20, 90)),
          mirrorHorizontally: true,
        ),
        HandMoveDirection.down,
      );
    });

    for (final testCase in const [
      (Offset(-90, 0), HandMoveDirection.left),
      (Offset(90, 0), HandMoveDirection.right),
      (Offset(0, -90), HandMoveDirection.up),
      (Offset(0, 90), HandMoveDirection.down),
    ]) {
      test(
        '${testCase.$2.name} accepts a compressed fold when its 2D angle fails',
        () {
          final hand = _pointingHand(
            indexVector: testCase.$1,
            landmarkOverrides: _compressedFingerOverrides(
              _fingerChains[1],
              const Offset(190, 225),
            ),
          );

          final result = switch (testCase.$2) {
            HandMoveDirection.left => _confirmMovingLeft(detector, hand),
            HandMoveDirection.right => _confirmMovingRight(detector, hand),
            HandMoveDirection.down => _confirmMovingDown(detector, hand),
            _ => _confirmMovingUp(detector, hand),
          };
          expect(result, testCase.$2);
        },
      );
    }

    test('one conflicting area measurement is tolerated as uncertain', () {
      final hand = _pointingHand(
        indexVector: const Offset(0, 90),
        landmarkOverrides: _compressedFingerOverrides(
          _fingerChains[1],
          const Offset(190, 225),
          tip: const Offset(225, 190),
        ),
      );

      expect(_confirmMovingDown(detector, hand), HandMoveDirection.down);
    });

    for (final testCase in const [
      (Offset(-90, 0), HandMoveDirection.left),
      (Offset(90, 0), HandMoveDirection.right),
    ]) {
      test('${testCase.$2.name} works with one confirmed folded finger', () {
        final hand = _pointingHand(
          indexVector: testCase.$1,
          missingTypes: const {
            HandLandmarkType.middleFingerMCP,
            HandLandmarkType.middleFingerPIP,
            HandLandmarkType.middleFingerDIP,
            HandLandmarkType.middleFingerTip,
            HandLandmarkType.ringFingerMCP,
            HandLandmarkType.ringFingerPIP,
            HandLandmarkType.ringFingerDIP,
            HandLandmarkType.ringFingerTip,
          },
        );

        final result =
            testCase.$2 == HandMoveDirection.left
                ? _confirmMovingLeft(detector, hand)
                : _confirmMovingRight(detector, hand);
        expect(result, testCase.$2);
        detector.clearState();
      });
    }
  });

  group('DirectionGestureDetector Moving Left 21-landmark replacement', () {
    late DirectionGestureDetector detector;

    setUp(() {
      detector = DirectionGestureDetector();
    });

    test('triggers on exactly the third consecutive matching frame', () {
      final hand = _pointingHand(indexVector: const Offset(-90, 0));

      expect(_detect(detector, hand), HandMoveDirection.none);
      expect(detector.debugSummary, contains('1/3'));
      expect(_detect(detector, hand), HandMoveDirection.none);
      expect(detector.debugSummary, contains('2/3'));
      expect(_detect(detector, hand), HandMoveDirection.left);
      expect(_detect(detector, hand), HandMoveDirection.left);
    });

    for (final angle in const [125.0, 180.0, 235.0]) {
      test('accepts the exact $angle degree screen direction', () {
        final hand = _pointingHand(
          indexVector: _vectorAtScreenDirectionDegrees(angle),
        );

        expect(_confirmMovingLeft(detector, hand), HandMoveDirection.left);
      });
    }

    for (final angle in const [124.0, 236.0]) {
      test('does not classify $angle degrees as moving left', () {
        final hand = _pointingHand(
          indexVector: _vectorAtScreenDirectionDegrees(angle),
        );

        for (var frame = 0; frame < 4; frame += 1) {
          expect(_detect(detector, hand), isNot(HandMoveDirection.left));
        }
      });
    }

    test('an interrupted match restarts all three confirmation frames', () {
      final validHand = _pointingHand(indexVector: const Offset(-90, 0));
      final invalidHand = _pointingHand(
        indexVector: const Offset(-90, 0),
        openOtherFingerIndexes: const {1, 2, 3},
      );

      expect(_detect(detector, validHand), HandMoveDirection.none);
      expect(_detect(detector, validHand), HandMoveDirection.none);
      expect(_detect(detector, invalidHand), HandMoveDirection.none);

      expect(_detect(detector, validHand), HandMoveDirection.none);
      expect(detector.debugSummary, contains('1/3'));
      expect(_detect(detector, validHand), HandMoveDirection.none);
      expect(_detect(detector, validHand), HandMoveDirection.left);
    });

    test('accepts either handedness and mirrored screen coordinates', () {
      expect(
        _confirmMovingLeft(
          detector,
          _pointingHand(
            indexVector: const Offset(-90, 0),
            handedness: Handedness.left,
          ),
        ),
        HandMoveDirection.left,
      );

      detector.clearState();

      expect(
        _confirmMovingLeft(
          detector,
          _pointingHand(indexVector: const Offset(90, 0)),
          mirrorHorizontally: true,
        ),
        HandMoveDirection.left,
      );
    });

    test('rejects either index joint below 145 degrees', () {
      final indexPoints = [
        _indexBase,
        _indexBase + const Offset(-30, 0),
        _indexBase + const Offset(-50, 20),
        _indexBase + const Offset(-90, 20),
      ];

      for (var frame = 0; frame < 4; frame += 1) {
        expect(
          _detect(detector, _pointingHand(indexPoints: indexPoints)),
          HandMoveDirection.none,
        );
      }
      expect(detector.debugSummary, contains('index joints'));
    });

    test('rejects an index tip that is not clearly left of the palm', () {
      final hand = _pointingHand(
        indexVector: const Offset(-90, 0),
        landmarkOverrides: const {HandLandmarkType.wrist: Offset(-500, 285)},
      );

      expect(_detect(detector, hand), HandMoveDirection.none);
      expect(detector.debugSummary, contains('tip not clearly left'));
    });

    test('allows an open middle finger when another finger is folded', () {
      final openMiddle = _pointingHand(
        indexVector: const Offset(-90, 0),
        openOtherFingerIndexes: const {1},
      );
      expect(_confirmMovingLeft(detector, openMiddle), HandMoveDirection.left);

      detector.clearState();

      final distantMiddleTip = _pointingHand(
        indexVector: const Offset(-90, 0),
        landmarkOverrides: const {
          HandLandmarkType.middleFingerTip: Offset(350, 50),
        },
      );
      expect(
        _confirmMovingLeft(detector, distantMiddleTip),
        HandMoveDirection.left,
      );
    });

    test('tolerates one unavailable folded finger landmark', () {
      final hand = _pointingHand(
        indexVector: const Offset(-90, 0),
        lowVisibilityTypes: const {HandLandmarkType.ringFingerDIP},
      );

      expect(_confirmMovingLeft(detector, hand), HandMoveDirection.left);
    });

    test(
      'tolerates one unavailable folded finger but requires point 0 and 5-8',
      () {
        expect(
          _confirmMovingLeft(
            detector,
            _pointingHand(
              indexVector: const Offset(-90, 0),
              missingTypes: const {
                HandLandmarkType.ringFingerMCP,
                HandLandmarkType.ringFingerPIP,
                HandLandmarkType.ringFingerDIP,
                HandLandmarkType.ringFingerTip,
              },
            ),
          ),
          HandMoveDirection.left,
        );

        detector.clearState();
        final missingIndexPoint = _pointingHand(
          indexVector: const Offset(-90, 0),
          lowVisibilityTypes: const {HandLandmarkType.indexFingerDIP},
        );
        expect(_detect(detector, missingIndexPoint), HandMoveDirection.none);
        expect(detector.debugSummary, contains('missing required point'));
      },
    );
  });

  group('DirectionGestureDetector Moving Right 21-landmark replacement', () {
    late DirectionGestureDetector detector;

    setUp(() {
      detector = DirectionGestureDetector();
    });

    test('triggers on exactly the third consecutive matching frame', () {
      final hand = _pointingHand(indexVector: const Offset(90, 0));

      expect(_detect(detector, hand), HandMoveDirection.none);
      expect(detector.debugSummary, contains('1/3'));
      expect(_detect(detector, hand), HandMoveDirection.none);
      expect(detector.debugSummary, contains('2/3'));
      expect(_detect(detector, hand), HandMoveDirection.right);
      expect(_detect(detector, hand), HandMoveDirection.right);
    });

    for (final angle in const [305.0, 0.0, 70.0]) {
      test('accepts the exact $angle degree screen direction', () {
        final hand = _pointingHand(
          indexVector: _vectorAtScreenDirectionDegrees(angle),
        );

        expect(_confirmMovingRight(detector, hand), HandMoveDirection.right);
      });
    }

    for (final angle in const [304.0, 71.0]) {
      test('does not classify $angle degrees as moving right', () {
        final hand = _pointingHand(
          indexVector: _vectorAtScreenDirectionDegrees(angle),
        );

        for (var frame = 0; frame < 4; frame += 1) {
          expect(_detect(detector, hand), isNot(HandMoveDirection.right));
        }
      });
    }

    test('an interrupted match restarts all three confirmation frames', () {
      final validHand = _pointingHand(indexVector: const Offset(90, 0));
      final invalidHand = _pointingHand(
        indexVector: const Offset(90, 0),
        openOtherFingerIndexes: const {1, 2, 3},
      );

      expect(_detect(detector, validHand), HandMoveDirection.none);
      expect(_detect(detector, validHand), HandMoveDirection.none);
      expect(_detect(detector, invalidHand), HandMoveDirection.none);

      expect(_detect(detector, validHand), HandMoveDirection.none);
      expect(detector.debugSummary, contains('1/3'));
      expect(_detect(detector, validHand), HandMoveDirection.none);
      expect(_detect(detector, validHand), HandMoveDirection.right);
    });

    test('accepts either handedness and mirrored screen coordinates', () {
      expect(
        _confirmMovingRight(
          detector,
          _pointingHand(
            indexVector: const Offset(90, 0),
            handedness: Handedness.left,
          ),
        ),
        HandMoveDirection.right,
      );

      detector.clearState();

      expect(
        _confirmMovingRight(
          detector,
          _pointingHand(indexVector: const Offset(-90, 0)),
          mirrorHorizontally: true,
        ),
        HandMoveDirection.right,
      );
    });

    test('accepts a rightward bend below the old 145 degree limit', () {
      final indexPoints = [
        _indexBase,
        _indexBase + const Offset(30, 0),
        _indexBase + const Offset(50, 20),
        _indexBase + const Offset(90, 20),
      ];

      expect(
        _confirmMovingRight(detector, _pointingHand(indexPoints: indexPoints)),
        HandMoveDirection.right,
      );
    });

    test('accepts the easier right bend after horizontal mirroring', () {
      final indexPoints = [
        _indexBase,
        _indexBase + const Offset(-30, 0),
        _indexBase + const Offset(-45, 26),
        _indexBase + const Offset(-60, 52),
      ];

      expect(
        _confirmMovingRight(
          detector,
          _pointingHand(indexPoints: indexPoints),
          mirrorHorizontally: true,
        ),
        HandMoveDirection.right,
      );
    });

    test('rejects an index tip that is not clearly right of the palm', () {
      final hand = _pointingHand(
        indexVector: const Offset(90, 0),
        landmarkOverrides: const {HandLandmarkType.wrist: Offset(1000, 285)},
      );

      expect(_detect(detector, hand), HandMoveDirection.none);
      expect(detector.debugSummary, contains('tip not clearly right'));
    });

    test('allows an open middle finger when another finger is folded', () {
      final openMiddle = _pointingHand(
        indexVector: const Offset(90, 0),
        openOtherFingerIndexes: const {1},
      );
      expect(
        _confirmMovingRight(detector, openMiddle),
        HandMoveDirection.right,
      );

      detector.clearState();

      final distantMiddleTip = _pointingHand(
        indexVector: const Offset(90, 0),
        landmarkOverrides: const {
          HandLandmarkType.middleFingerTip: Offset(350, 50),
        },
      );
      expect(
        _confirmMovingRight(detector, distantMiddleTip),
        HandMoveDirection.right,
      );
    });

    test('tolerates one unavailable folded finger landmark', () {
      final hand = _pointingHand(
        indexVector: const Offset(90, 0),
        lowVisibilityTypes: const {HandLandmarkType.ringFingerDIP},
      );

      expect(_confirmMovingRight(detector, hand), HandMoveDirection.right);
    });

    test(
      'tolerates one unavailable folded finger but requires point 0 and 5-8',
      () {
        expect(
          _confirmMovingRight(
            detector,
            _pointingHand(
              indexVector: const Offset(90, 0),
              missingTypes: const {
                HandLandmarkType.ringFingerMCP,
                HandLandmarkType.ringFingerPIP,
                HandLandmarkType.ringFingerDIP,
                HandLandmarkType.ringFingerTip,
              },
            ),
          ),
          HandMoveDirection.right,
        );

        detector.clearState();
        final missingWrist = _pointingHand(
          indexVector: const Offset(90, 0),
          missingTypes: const {HandLandmarkType.wrist},
        );
        expect(_detect(detector, missingWrist), HandMoveDirection.none);
        expect(detector.debugSummary, contains('missing required point'));
      },
    );

    test('ignores missing and extended thumb landmarks', () {
      expect(
        _confirmMovingRight(
          detector,
          _pointingHand(indexVector: const Offset(90, 0), includeThumb: false),
        ),
        HandMoveDirection.right,
      );

      detector.clearState();

      expect(
        _confirmMovingRight(
          detector,
          _pointingHand(
            indexVector: const Offset(90, 0),
            includeThumb: true,
            thumbTip: const Offset(105, 155),
          ),
        ),
        HandMoveDirection.right,
      );
    });

    test('reserves a touching bent-right pinch for Zoom Out', () {
      final indexPoints = [
        _indexBase,
        _indexBase + const Offset(30, 0),
        _indexBase + const Offset(45, 26),
        _indexBase + const Offset(60, 52),
      ];
      final hand = _pointingHand(
        indexPoints: indexPoints,
        includeThumb: true,
        landmarkOverrides: const {
          HandLandmarkType.thumbMCP: Offset(220, 250),
          HandLandmarkType.thumbIP: Offset(240, 245),
          HandLandmarkType.thumbTip: Offset(260, 257),
        },
      );

      expect(_detect(detector, hand), HandMoveDirection.none);
      expect(detector.debugSummary, contains('zoom-out closed pinch'));

      final zoomDetector = ZoomGestureDetector(
        now: () => DateTime.utc(2026, 7, 19),
      );
      expect(
        zoomDetector.detect(
          hand: hand,
          imageSize: _imageSize,
          mirrorHorizontally: false,
        ),
        ZoomDirection.none,
      );
      expect(zoomDetector.pendingDirection, ZoomDirection.zoomOut);
    });

    test('does not reserve a back-side touching pinch for Zoom Out', () {
      final indexPoints = [
        _indexBase,
        _indexBase + const Offset(30, 0),
        _indexBase + const Offset(45, 26),
        _indexBase + const Offset(60, 52),
      ];
      final hand = _pointingHand(
        indexPoints: indexPoints,
        includeThumb: true,
        landmarkOverrides: const {
          HandLandmarkType.wrist: Offset(210, 150),
          HandLandmarkType.thumbMCP: Offset(220, 250),
          HandLandmarkType.thumbIP: Offset(240, 245),
          HandLandmarkType.thumbTip: Offset(260, 257),
        },
      );

      expect(_confirmMovingRight(detector, hand), HandMoveDirection.right);
      expect(detector.debugSummary, isNot(contains('zoom-out closed pinch')));
    });
  });

  group('DirectionGestureDetector Moving Up 21-landmark replacement', () {
    late DirectionGestureDetector detector;

    setUp(() {
      detector = DirectionGestureDetector();
    });

    test('triggers on the third steady matching frame', () {
      final hand = _pointingHand(indexVector: const Offset(0, -90));

      expect(_detect(detector, hand), HandMoveDirection.none);
      expect(_detect(detector, hand), HandMoveDirection.none);
      expect(_detect(detector, hand), HandMoveDirection.up);
    });

    for (final angle in const [75.0, 90.0, 120.0]) {
      test('accepts the exact initial $angle degree screen direction', () {
        final hand = _pointingHand(
          indexVector: _vectorAtScreenDirectionDegrees(angle),
        );

        expect(_confirmMovingUp(detector, hand), HandMoveDirection.up);
      });
    }

    for (final angle in const [74.0, 121.0]) {
      test('does not initially classify $angle degrees as moving up', () {
        final hand = _pointingHand(
          indexVector: _vectorAtScreenDirectionDegrees(angle),
        );

        expect(_detect(detector, hand), isNot(HandMoveDirection.up));
      });
    }

    test('retains active moving up throughout 70 to 125 degrees', () {
      expect(
        _confirmMovingUp(
          detector,
          _pointingHand(indexVector: const Offset(0, -90)),
        ),
        HandMoveDirection.up,
      );

      expect(
        _detect(
          detector,
          _pointingHand(indexVector: _vectorAtScreenDirectionDegrees(70)),
        ),
        HandMoveDirection.up,
      );
      expect(
        _detect(
          detector,
          _pointingHand(indexVector: _vectorAtScreenDirectionDegrees(125)),
        ),
        HandMoveDirection.up,
      );
    });

    test('leaving the active range ends moving up immediately', () {
      expect(
        _confirmMovingUp(
          detector,
          _pointingHand(indexVector: const Offset(0, -90)),
        ),
        HandMoveDirection.up,
      );

      expect(
        _detect(
          detector,
          _pointingHand(indexVector: _vectorAtScreenDirectionDegrees(126)),
        ),
        HandMoveDirection.none,
      );
      expect(detector.debugSummary, contains('confirming left 1/3'));
    });

    test('ignores wrist position and missing wrist landmark', () {
      for (final wrist in const [
        Offset(210, 50),
        Offset(210, 390),
        Offset(20, 220),
        Offset(390, 220),
      ]) {
        detector.clearState();
        expect(
          _confirmMovingUp(
            detector,
            _pointingHand(
              indexVector: const Offset(0, -90),
              landmarkOverrides: {HandLandmarkType.wrist: wrist},
            ),
          ),
          HandMoveDirection.up,
        );
      }

      detector.clearState();
      expect(
        _confirmMovingUp(
          detector,
          _pointingHand(
            indexVector: const Offset(0, -90),
            missingTypes: const {HandLandmarkType.wrist},
          ),
        ),
        HandMoveDirection.up,
      );
    });

    test('accepts either handedness and mirrored screen coordinates', () {
      expect(
        _confirmMovingUp(
          detector,
          _pointingHand(
            indexVector: const Offset(0, -90),
            handedness: Handedness.left,
          ),
        ),
        HandMoveDirection.up,
      );

      detector.clearState();

      expect(
        _confirmMovingUp(
          detector,
          _pointingHand(indexVector: const Offset(0, -90)),
          mirrorHorizontally: true,
        ),
        HandMoveDirection.up,
      );
    });

    test('rejects an index joint below its required straightness', () {
      final indexPoints = [
        _indexBase,
        _indexBase + const Offset(0, -30),
        _indexBase + const Offset(20, -50),
        _indexBase + const Offset(0, -90),
      ];

      expect(
        _confirmMovingUp(detector, _pointingHand(indexPoints: indexPoints)),
        HandMoveDirection.none,
      );
      expect(detector.debugSummary, contains('index joints'));
    });

    test('keeps the 135 degree 5-6-7 boundary for moving up', () {
      final indexPoints = [
        _indexBase,
        _indexBase + const Offset(25, -25),
        _indexBase + const Offset(25, -60),
        _indexBase + const Offset(20, -95),
      ];

      expect(
        _confirmMovingUp(detector, _pointingHand(indexPoints: indexPoints)),
        HandMoveDirection.up,
      );
    });

    for (final angle in const [170.0, 180.0]) {
      test('accepts a 6-7-8 angle of $angle degrees for moving up', () {
        final hand = _pointingHand(
          indexPoints: _indexPointsWithDistalAngle(const Offset(0, -90), angle),
        );

        expect(_confirmMovingUp(detector, hand), HandMoveDirection.up);
      });
    }

    test('rejects a 6-7-8 angle below 170 degrees for moving up', () {
      final hand = _pointingHand(
        indexPoints: _indexPointsWithDistalAngle(const Offset(0, -90), 169),
      );

      expect(_detect(detector, hand), HandMoveDirection.none);
      expect(detector.debugSummary, contains('169.0'));
    });

    test('requires points 5, 6, 7, and 8 to rise in order', () {
      final indexPoints = [
        _indexBase,
        const Offset(200, 155),
        const Offset(200, 165),
        const Offset(200, 115),
      ];

      expect(
        _detect(detector, _pointingHand(indexPoints: indexPoints)),
        HandMoveDirection.none,
      );
      expect(detector.debugSummary, contains('do not rise in order'));
    });

    test('rejects points 5-8 that spread too far from the y-axis', () {
      final indexPoints = [
        _indexBase,
        const Offset(280, 180),
        const Offset(200, 150),
        const Offset(200, 115),
      ];

      expect(
        _detect(detector, _pointingHand(indexPoints: indexPoints)),
        HandMoveDirection.none,
      );
      expect(detector.debugSummary, contains('not aligned with the y-axis'));
    });

    test('allows an open middle finger when another finger is folded', () {
      final openMiddle = _pointingHand(
        indexVector: const Offset(0, -90),
        openOtherFingerIndexes: const {1},
      );
      expect(_confirmMovingUp(detector, openMiddle), HandMoveDirection.up);

      detector.clearState();

      final distantMiddleTip = _pointingHand(
        indexVector: const Offset(0, -90),
        landmarkOverrides: const {
          HandLandmarkType.middleFingerTip: Offset(350, 50),
        },
      );
      expect(
        _confirmMovingUp(detector, distantMiddleTip),
        HandMoveDirection.up,
      );
    });

    test('tolerates one unavailable folded finger but requires points 5-8', () {
      expect(
        _confirmMovingUp(
          detector,
          _pointingHand(
            indexVector: const Offset(0, -90),
            missingTypes: const {
              HandLandmarkType.ringFingerMCP,
              HandLandmarkType.ringFingerPIP,
              HandLandmarkType.ringFingerDIP,
              HandLandmarkType.ringFingerTip,
            },
          ),
        ),
        HandMoveDirection.up,
      );

      detector.clearState();
      final missingIndexPoint = _pointingHand(
        indexVector: const Offset(0, -90),
        lowVisibilityTypes: const {HandLandmarkType.indexFingerDIP},
      );
      expect(_detect(detector, missingIndexPoint), HandMoveDirection.none);
      expect(
        detector.debugSummary,
        contains('missing required index point 5-8'),
      );
    });

    test('tolerates one unavailable folded finger landmark', () {
      final hand = _pointingHand(
        indexVector: const Offset(0, -90),
        lowVisibilityTypes: const {HandLandmarkType.middleFingerDIP},
      );

      expect(_confirmMovingUp(detector, hand), HandMoveDirection.up);
    });

    test('accepts a congested folded finger for moving up too', () {
      final hand = _pointingHand(
        indexVector: const Offset(0, -90),
        landmarkOverrides: const {
          HandLandmarkType.middleFingerPIP: Offset(190, 210),
          HandLandmarkType.middleFingerDIP: Offset(190, 209),
          HandLandmarkType.middleFingerTip: Offset(191, 208),
        },
      );

      expect(_confirmMovingUp(detector, hand), HandMoveDirection.up);
    });

    test('accepts one visible folded finger for moving up', () {
      final hand = _pointingHand(
        indexVector: const Offset(0, -90),
        missingTypes: const {
          HandLandmarkType.middleFingerMCP,
          HandLandmarkType.middleFingerPIP,
          HandLandmarkType.middleFingerDIP,
          HandLandmarkType.middleFingerTip,
          HandLandmarkType.ringFingerMCP,
          HandLandmarkType.ringFingerPIP,
          HandLandmarkType.ringFingerDIP,
          HandLandmarkType.ringFingerTip,
        },
      );

      expect(_confirmMovingUp(detector, hand), HandMoveDirection.up);
    });

    for (final angle in const [155.0, 156.0]) {
      test('$angle degree open middle does not block moving up', () {
        final hand = _pointingHand(
          indexVector: const Offset(0, -90),
          landmarkOverrides: _fingerJointOverrides(
            _fingerChains[1],
            const Offset(190, 225),
            angle,
          ),
        );

        expect(_confirmMovingUp(detector, hand), HandMoveDirection.up);
      });
    }

    test(
      'ignores a missing thumb and does not yield an axis intersection to zoom',
      () {
        expect(
          _confirmMovingUp(
            detector,
            _pointingHand(
              indexVector: const Offset(0, -90),
              includeThumb: false,
            ),
          ),
          HandMoveDirection.up,
        );

        detector.clearState();

        expect(
          _confirmMovingUp(
            detector,
            _pointingHand(
              indexVector: const Offset(0, -90),
              includeThumb: true,
              thumbTip: const Offset(105, 155),
              landmarkOverrides: const {HandLandmarkType.wrist: Offset(0, 285)},
            ),
          ),
          HandMoveDirection.up,
        );
        expect(detector.debugSummary, isNot(contains('zoom-in thumb/index')));
      },
    );
  });

  group('DirectionGestureDetector Moving Down 21-landmark replacement', () {
    late DirectionGestureDetector detector;

    setUp(() {
      detector = DirectionGestureDetector();
    });

    test('triggers on exactly the third consecutive matching frame', () {
      final hand = _pointingHand(indexVector: const Offset(0, 90));

      expect(_detect(detector, hand), HandMoveDirection.none);
      expect(detector.debugSummary, contains('1/3'));
      expect(_detect(detector, hand), HandMoveDirection.none);
      expect(detector.debugSummary, contains('2/3'));
      expect(_detect(detector, hand), HandMoveDirection.down);
      expect(_detect(detector, hand), HandMoveDirection.down);
    });

    for (final angle in const [245.0, 270.0, 295.0]) {
      test('accepts the exact initial $angle degree screen direction', () {
        final hand = _pointingHand(
          indexVector: _vectorAtScreenDirectionDegrees(angle),
        );

        expect(_confirmMovingDown(detector, hand), HandMoveDirection.down);
      });
    }

    for (final angle in const [244.0, 296.0]) {
      test('does not initially classify $angle degrees as moving down', () {
        final hand = _pointingHand(
          indexVector: _vectorAtScreenDirectionDegrees(angle),
        );

        for (var frame = 0; frame < 4; frame += 1) {
          expect(_detect(detector, hand), isNot(HandMoveDirection.down));
        }
      });
    }

    test('retains active moving down throughout 235 to 305 degrees', () {
      expect(
        _confirmMovingDown(
          detector,
          _pointingHand(indexVector: const Offset(0, 90)),
        ),
        HandMoveDirection.down,
      );

      expect(
        _detect(
          detector,
          _pointingHand(indexVector: _vectorAtScreenDirectionDegrees(235)),
        ),
        HandMoveDirection.down,
      );
      expect(
        _detect(
          detector,
          _pointingHand(indexVector: _vectorAtScreenDirectionDegrees(305)),
        ),
        HandMoveDirection.down,
      );
    });

    test('leaving the active range ends moving down immediately', () {
      expect(
        _confirmMovingDown(
          detector,
          _pointingHand(indexVector: const Offset(0, 90)),
        ),
        HandMoveDirection.down,
      );

      expect(
        _detect(
          detector,
          _pointingHand(indexVector: _vectorAtScreenDirectionDegrees(310)),
        ),
        HandMoveDirection.none,
      );
      expect(detector.debugSummary, contains('confirming right 1/3'));
    });

    test('an interrupted match restarts all three confirmation frames', () {
      final validHand = _pointingHand(indexVector: const Offset(0, 90));
      final invalidHand = _pointingHand(
        indexVector: const Offset(0, 90),
        openOtherFingerIndexes: const {1, 2, 3},
      );

      expect(_detect(detector, validHand), HandMoveDirection.none);
      expect(_detect(detector, validHand), HandMoveDirection.none);
      expect(_detect(detector, invalidHand), HandMoveDirection.none);

      expect(_detect(detector, validHand), HandMoveDirection.none);
      expect(detector.debugSummary, contains('1/3'));
      expect(_detect(detector, validHand), HandMoveDirection.none);
      expect(_detect(detector, validHand), HandMoveDirection.down);
    });

    test('ignores wrist position and missing wrist landmark', () {
      for (final wrist in const [
        Offset(210, 50),
        Offset(210, 390),
        Offset(20, 220),
        Offset(390, 220),
      ]) {
        detector.clearState();
        expect(
          _confirmMovingDown(
            detector,
            _pointingHand(
              indexVector: const Offset(0, 90),
              landmarkOverrides: {HandLandmarkType.wrist: wrist},
            ),
          ),
          HandMoveDirection.down,
        );
      }

      detector.clearState();
      expect(
        _confirmMovingDown(
          detector,
          _pointingHand(
            indexVector: const Offset(0, 90),
            missingTypes: const {HandLandmarkType.wrist},
          ),
        ),
        HandMoveDirection.down,
      );
    });

    test('accepts either handedness and mirrored screen coordinates', () {
      expect(
        _confirmMovingDown(
          detector,
          _pointingHand(
            indexVector: const Offset(20, 90),
            handedness: Handedness.left,
          ),
        ),
        HandMoveDirection.down,
      );

      detector.clearState();

      expect(
        _confirmMovingDown(
          detector,
          _pointingHand(indexVector: const Offset(20, 90)),
          mirrorHorizontally: true,
        ),
        HandMoveDirection.down,
      );
    });

    test('ignores point 5 direction when points 6-8 point down', () {
      final indexPoints = [
        _indexBase,
        _indexBase + const Offset(30, 0),
        _indexBase + const Offset(32, 40),
        _indexBase + const Offset(29, 80),
      ];

      expect(
        _confirmMovingDown(detector, _pointingHand(indexPoints: indexPoints)),
        HandMoveDirection.down,
      );
    });

    test('requires points 6, 7, and 8 to descend in order', () {
      final indexPoints = [
        _indexBase,
        const Offset(200, 235),
        const Offset(200, 285),
        const Offset(200, 275),
      ];

      expect(
        _detect(detector, _pointingHand(indexPoints: indexPoints)),
        HandMoveDirection.none,
      );
      expect(detector.debugSummary, contains('do not descend in order'));
    });

    test('rejects a sharp bend inside points 6-8', () {
      final indexPoints = [
        _indexBase,
        const Offset(200, 235),
        const Offset(210, 255),
        const Offset(200, 256),
      ];

      expect(
        _detect(detector, _pointingHand(indexPoints: indexPoints)),
        HandMoveDirection.none,
      );
      expect(detector.debugSummary, contains('points 6-8 joint'));
    });

    for (final angle in const [170.0, 180.0]) {
      test('accepts a 6-7-8 angle of $angle degrees for moving down', () {
        final hand = _pointingHand(
          indexPoints: _indexPointsWithDistalAngle(const Offset(0, 90), angle),
        );

        expect(_confirmMovingDown(detector, hand), HandMoveDirection.down);
      });
    }

    test('rejects a 6-7-8 angle below 170 degrees for moving down', () {
      final hand = _pointingHand(
        indexPoints: _indexPointsWithDistalAngle(const Offset(0, 90), 169),
      );

      expect(_detect(detector, hand), HandMoveDirection.none);
      expect(detector.debugSummary, contains('169.0'));
    });

    test('rejects points 6-8 that spread too far from the y-axis', () {
      final indexPoints = [
        _indexBase,
        const Offset(200, 235),
        const Offset(240, 260),
        const Offset(200, 285),
      ];

      expect(
        _detect(detector, _pointingHand(indexPoints: indexPoints)),
        HandMoveDirection.none,
      );
      expect(detector.debugSummary, contains('not aligned with the y-axis'));
    });

    test('allows an open middle finger when another finger is folded', () {
      final openMiddle = _pointingHand(
        indexVector: const Offset(0, 90),
        openOtherFingerIndexes: const {1},
      );
      expect(_confirmMovingDown(detector, openMiddle), HandMoveDirection.down);

      detector.clearState();

      final distantMiddleTip = _pointingHand(
        indexVector: const Offset(0, 90),
        landmarkOverrides: const {
          HandLandmarkType.middleFingerTip: Offset(350, 50),
        },
      );
      expect(
        _confirmMovingDown(detector, distantMiddleTip),
        HandMoveDirection.down,
      );
    });

    for (final clusteredFinger in const [
      (
        'middle',
        HandLandmarkType.middleFingerPIP,
        HandLandmarkType.middleFingerDIP,
        HandLandmarkType.middleFingerTip,
        Offset(190, 210),
        Offset(190, 209),
        Offset(191, 208),
      ),
      (
        'ring',
        HandLandmarkType.ringFingerPIP,
        HandLandmarkType.ringFingerDIP,
        HandLandmarkType.ringFingerTip,
        Offset(215, 210),
        Offset(215, 209),
        Offset(216, 208),
      ),
      (
        'pinky',
        HandLandmarkType.pinkyPIP,
        HandLandmarkType.pinkyDIP,
        HandLandmarkType.pinkyTip,
        Offset(240, 205),
        Offset(240, 204),
        Offset(241, 203),
      ),
    ]) {
      test(
        'accepts a folded ${clusteredFinger.$1} whose top three points cluster near its MCP',
        () {
          final hand = _pointingHand(
            indexVector: const Offset(0, 90),
            landmarkOverrides: {
              clusteredFinger.$2: clusteredFinger.$5,
              clusteredFinger.$3: clusteredFinger.$6,
              clusteredFinger.$4: clusteredFinger.$7,
            },
          );

          expect(_confirmMovingDown(detector, hand), HandMoveDirection.down);
        },
      );
    }

    test(
      'allows a non-folded compact cluster when another finger is folded',
      () {
        final hand = _pointingHand(
          indexVector: const Offset(0, 90),
          landmarkOverrides: const {
            HandLandmarkType.middleFingerPIP: Offset(300, 100),
            HandLandmarkType.middleFingerDIP: Offset(301, 99),
            HandLandmarkType.middleFingerTip: Offset(302, 98),
          },
        );

        expect(_confirmMovingDown(detector, hand), HandMoveDirection.down);
      },
    );

    test('allows non-congested top points when another finger is folded', () {
      final hand = _pointingHand(
        indexVector: const Offset(0, 90),
        landmarkOverrides: const {
          HandLandmarkType.middleFingerPIP: Offset(190, 210),
          HandLandmarkType.middleFingerDIP: Offset(190, 209),
          HandLandmarkType.middleFingerTip: Offset(225, 180),
        },
      );

      expect(_confirmMovingDown(detector, hand), HandMoveDirection.down);
    });

    test('tolerates one depth-conflicted finger as uncertain', () {
      final hand = _pointingHand(
        indexVector: const Offset(0, 90),
        landmarkOverrides: const {
          HandLandmarkType.middleFingerPIP: Offset(190, 210),
          HandLandmarkType.middleFingerDIP: Offset(190, 209),
          HandLandmarkType.middleFingerTip: Offset(191, 208),
        },
        landmarkDepthOverrides: const {HandLandmarkType.middleFingerTip: 100},
      );

      expect(_confirmMovingDown(detector, hand), HandMoveDirection.down);
    });

    test('accepts when one finger is folded and two are uncertain', () {
      final hand = _pointingHand(
        indexVector: const Offset(0, 90),
        landmarkOverrides: const {
          HandLandmarkType.middleFingerPIP: Offset(190, 210),
          HandLandmarkType.middleFingerDIP: Offset(190, 209),
          HandLandmarkType.middleFingerTip: Offset(191, 208),
          HandLandmarkType.ringFingerPIP: Offset(215, 210),
          HandLandmarkType.ringFingerDIP: Offset(215, 209),
          HandLandmarkType.ringFingerTip: Offset(216, 208),
        },
        landmarkDepthOverrides: const {
          HandLandmarkType.middleFingerTip: 100,
          HandLandmarkType.ringFingerTip: 100,
        },
      );

      expect(_confirmMovingDown(detector, hand), HandMoveDirection.down);
    });

    test('ignores point 5, tolerates one folded finger loss, requires 6-8', () {
      expect(
        _confirmMovingDown(
          detector,
          _pointingHand(
            indexVector: const Offset(0, 90),
            missingTypes: const {HandLandmarkType.indexFingerMCP},
          ),
        ),
        HandMoveDirection.down,
      );

      detector.clearState();

      expect(
        _confirmMovingDown(
          detector,
          _pointingHand(
            indexVector: const Offset(0, 90),
            missingTypes: const {
              HandLandmarkType.middleFingerMCP,
              HandLandmarkType.middleFingerPIP,
              HandLandmarkType.middleFingerDIP,
              HandLandmarkType.middleFingerTip,
            },
          ),
        ),
        HandMoveDirection.down,
      );

      detector.clearState();

      final missingIndexPoint = _pointingHand(
        indexVector: const Offset(0, 90),
        missingTypes: const {HandLandmarkType.indexFingerDIP},
      );
      expect(_detect(detector, missingIndexPoint), HandMoveDirection.none);
      expect(
        detector.debugSummary,
        contains('missing required index point 6-8'),
      );
    });

    test('tolerates one unavailable folded finger landmark', () {
      final hand = _pointingHand(
        indexVector: const Offset(0, 90),
        lowVisibilityTypes: const {HandLandmarkType.middleFingerDIP},
      );

      expect(_confirmMovingDown(detector, hand), HandMoveDirection.down);
    });

    test('accepts when only one folded finger remains visible for down', () {
      final hand = _pointingHand(
        indexVector: const Offset(0, 90),
        missingTypes: const {
          HandLandmarkType.middleFingerMCP,
          HandLandmarkType.middleFingerPIP,
          HandLandmarkType.middleFingerDIP,
          HandLandmarkType.middleFingerTip,
          HandLandmarkType.ringFingerMCP,
          HandLandmarkType.ringFingerPIP,
          HandLandmarkType.ringFingerDIP,
          HandLandmarkType.ringFingerTip,
        },
      );

      expect(_confirmMovingDown(detector, hand), HandMoveDirection.down);
    });

    for (final angle in const [155.0, 156.0]) {
      test('$angle degree open middle does not block moving down', () {
        final hand = _pointingHand(
          indexVector: const Offset(0, 90),
          landmarkOverrides: _fingerJointOverrides(
            _fingerChains[1],
            const Offset(190, 225),
            angle,
          ),
        );

        expect(_confirmMovingDown(detector, hand), HandMoveDirection.down);
      });
    }

    test('ignores missing and extended thumb landmarks', () {
      expect(
        _confirmMovingDown(
          detector,
          _pointingHand(indexVector: const Offset(0, 90), includeThumb: false),
        ),
        HandMoveDirection.down,
      );

      detector.clearState();

      expect(
        _confirmMovingDown(
          detector,
          _pointingHand(
            indexVector: const Offset(0, 90),
            includeThumb: true,
            thumbTip: const Offset(105, 155),
          ),
        ),
        HandMoveDirection.down,
      );
    });
  });

  group('DirectionGestureDetector pointing pose', () {
    late DirectionGestureDetector detector;

    setUp(() {
      detector = DirectionGestureDetector();
    });

    for (final testCase in const [
      (0.0, HandMoveDirection.right, HandMoveDirection.right),
      (90.0, HandMoveDirection.up, HandMoveDirection.none),
      (180.0, HandMoveDirection.left, HandMoveDirection.left),
      (270.0, HandMoveDirection.down, HandMoveDirection.none),
    ]) {
      test('${testCase.$3 == HandMoveDirection.none ? 'rejects' : 'accepts'} '
          'an approximately 150 degree index for ${testCase.$2.name}', () {
        final hand = _pointingHand(
          indexPoints: _moderatelyBentIndexPoints(testCase.$1),
        );
        final result = switch (testCase.$2) {
          HandMoveDirection.left => _confirmMovingLeft(detector, hand),
          HandMoveDirection.right => _confirmMovingRight(detector, hand),
          HandMoveDirection.down => _confirmMovingDown(detector, hand),
          _ => _confirmMovingUp(detector, hand),
        };

        expect(result, testCase.$3);
      });
    }

    test('moving right accepts an index bent to approximately 138 degrees', () {
      final indexPoints = [
        _indexBase,
        _indexBase + const Offset(30, 0),
        _indexBase + const Offset(52, 20),
        _indexBase + const Offset(75, 40),
      ];

      expect(
        _confirmMovingRight(detector, _pointingHand(indexPoints: indexPoints)),
        HandMoveDirection.right,
      );
    });

    test('uses the easier bend rule for moving right', () {
      final indexPoints = [
        _indexBase,
        _indexBase + const Offset(30, 0),
        _indexBase + const Offset(45, 26),
        _indexBase + const Offset(60, 52),
      ];

      expect(
        _confirmMovingRight(detector, _pointingHand(indexPoints: indexPoints)),
        HandMoveDirection.right,
      );
    });

    test('rejects a clearly folded index in every direction', () {
      final indexPoints = [
        _indexBase,
        _indexBase + const Offset(70, 0),
        _indexBase + const Offset(75, 30),
        _indexBase + const Offset(80, 57),
      ];

      expect(
        _detect(detector, _pointingHand(indexPoints: indexPoints)),
        HandMoveDirection.none,
      );
      expect(detector.debugSummary, contains('straightness'));
    });

    test('accepts a short index when its tip is clearly right of the palm', () {
      expect(
        _confirmMovingRight(
          detector,
          _pointingHand(indexVector: const Offset(39, 0)),
        ),
        HandMoveDirection.right,
      );
    });

    for (final fingerIndex in const [1, 2, 3]) {
      test('accepts pose when only finger $fingerIndex is open', () {
        expect(
          _confirmMovingRight(
            detector,
            _pointingHand(openOtherFingerIndexes: {fingerIndex}),
          ),
          HandMoveDirection.right,
        );
        detector.clearState();
      });
    }

    for (final testCase in const [
      (Offset(-90, 0), HandMoveDirection.left),
      (Offset(0, -90), HandMoveDirection.up),
      (Offset(90, 0), HandMoveDirection.right),
      (Offset(0, 90), HandMoveDirection.down),
    ]) {
      test('${testCase.$2.name} accepts one folded and two open fingers', () {
        final hand = _pointingHand(
          indexVector: testCase.$1,
          openOtherFingerIndexes: const {1, 2},
        );
        final result = switch (testCase.$2) {
          HandMoveDirection.left => _confirmMovingLeft(detector, hand),
          HandMoveDirection.right => _confirmMovingRight(detector, hand),
          HandMoveDirection.down => _confirmMovingDown(detector, hand),
          _ => _confirmMovingUp(detector, hand),
        };

        expect(result, testCase.$2);
        detector.clearState();
      });
    }

    for (final testCase in const [
      (Offset(-90, 0), HandMoveDirection.left),
      (Offset(0, -90), HandMoveDirection.up),
      (Offset(90, 0), HandMoveDirection.right),
      (Offset(0, 90), HandMoveDirection.down),
    ]) {
      test(
        '${testCase.$2.name} accepts the compact palm circle with zero folded fingers',
        () {
          final hand = _pointingHand(
            indexVector: testCase.$1,
            landmarkOverrides: _compactOtherFingerOverrides(),
          );
          final result = switch (testCase.$2) {
            HandMoveDirection.left => _confirmMovingLeft(detector, hand),
            HandMoveDirection.right => _confirmMovingRight(detector, hand),
            HandMoveDirection.down => _confirmMovingDown(detector, hand),
            _ => _confirmMovingUp(detector, hand),
          };

          expect(result, testCase.$2);
          detector.clearState();
        },
      );
    }

    test('horizontal compact pose uses the frame minimum-radius clamp', () {
      final hand = _pointingHand(
        indexVector: const Offset(90, 0),
        landmarkOverrides: _compactOtherFingerOverrides(),
      );

      expect(
        _confirmMovingRight(detector, hand, imageSize: const Size(200, 200)),
        HandMoveDirection.none,
      );
      detector.clearState();
      expect(
        _confirmMovingRight(detector, hand, imageSize: _imageSize),
        HandMoveDirection.right,
      );
    });

    test('vertical compact pose uses the frame minimum-radius clamp', () {
      final hand = _pointingHand(
        indexVector: const Offset(0, -90),
        landmarkOverrides: _compactOtherFingerOverrides(),
      );

      expect(
        _confirmMovingUp(detector, hand, imageSize: const Size(200, 200)),
        HandMoveDirection.none,
      );
      detector.clearState();
      expect(
        _confirmMovingUp(detector, hand, imageSize: _imageSize),
        HandMoveDirection.up,
      );
    });

    test('zero folded fingers fail when one point leaves the palm circle', () {
      final overrides =
          _compactOtherFingerOverrides()
            ..[HandLandmarkType.pinkyTip] = const Offset(240, 125);

      expect(
        _confirmMovingRight(
          detector,
          _pointingHand(landmarkOverrides: overrides),
        ),
        HandMoveDirection.none,
      );
      expect(detector.debugSummary, contains('compact palm circle failed'));
    });

    test('moving right ignores the thumb position', () {
      expect(
        _confirmMovingRight(
          detector,
          _pointingHand(includeThumb: true, thumbTip: const Offset(195, 225)),
        ),
        HandMoveDirection.right,
      );

      detector.clearState();

      expect(
        _confirmMovingRight(
          detector,
          _pointingHand(includeThumb: true, thumbTip: const Offset(105, 155)),
        ),
        HandMoveDirection.right,
      );
    });

    test('moving left ignores missing and extended thumb landmarks', () {
      expect(
        _confirmMovingLeft(
          detector,
          _pointingHand(indexVector: const Offset(-90, 0), includeThumb: false),
        ),
        HandMoveDirection.left,
      );

      detector.clearState();

      expect(
        _confirmMovingLeft(
          detector,
          _pointingHand(
            indexVector: const Offset(-90, 0),
            includeThumb: true,
            thumbTip: const Offset(105, 235),
          ),
        ),
        HandMoveDirection.left,
      );
    });

    test('rejects a fully folded index even when its tip projects right', () {
      final indexPoints = [
        _indexBase,
        _indexBase + const Offset(30, 0),
        _indexBase + const Offset(24, 12),
        _indexBase + const Offset(40, 25),
      ];

      expect(
        _detect(detector, _pointingHand(indexPoints: indexPoints)),
        HandMoveDirection.none,
      );
      expect(detector.debugSummary, contains('straightness'));
    });

    test('preserves screen direction under a large index-depth change', () {
      expect(
        _confirmMovingRight(detector, _pointingHand(indexDepthVector: 240)),
        HandMoveDirection.right,
      );
    });

    for (final testCase in const [
      (Offset(-90, 0), HandMoveDirection.left),
      (Offset(0, -90), HandMoveDirection.up),
      (Offset(90, 0), HandMoveDirection.right),
      (Offset(0, 90), HandMoveDirection.down),
    ]) {
      test('z movement does not change ${testCase.$2.name}', () {
        final hand = _pointingHand(
          indexVector: testCase.$1,
          indexDepthVector: -300,
        );
        final result = switch (testCase.$2) {
          HandMoveDirection.left => _confirmMovingLeft(detector, hand),
          HandMoveDirection.right => _confirmMovingRight(detector, hand),
          HandMoveDirection.down => _confirmMovingDown(detector, hand),
          _ => _confirmMovingUp(detector, hand),
        };
        expect(result, testCase.$2);
      });
    }

    test('maps a reliable package pointingUp result directly to moving up', () {
      final hand = _pointingHand(
        indexVector: const Offset(90, 0),
        openOtherFingerIndexes: const {1, 2, 3},
        gesture: const GestureResult(
          type: GestureType.pointingUp,
          confidence: 1,
        ),
      );

      expect(_confirmMovingUp(detector, hand), HandMoveDirection.up);
      expect(detector.debugSummary, contains('package pointingUp'));
    });

    test('does not trust a low-confidence package pointingUp result', () {
      final hand = _pointingHand(
        indexVector: const Offset(90, 0),
        openOtherFingerIndexes: const {1, 2, 3},
        gesture: const GestureResult(
          type: GestureType.pointingUp,
          confidence: 0.1,
        ),
      );

      expect(_detect(detector, hand), HandMoveDirection.none);
      expect(detector.debugSummary, isNot(contains('package pointingUp')));
    });

    test('allows a package thumbDown result to produce moving down', () {
      final hand = _pointingHand(
        indexVector: const Offset(0, 90),
        gesture: const GestureResult(
          type: GestureType.thumbDown,
          confidence: 1,
        ),
      );

      expect(_confirmMovingDown(detector, hand), HandMoveDirection.down);
    });

    test('legacy multi-finger pointing does not trigger a direction', () {
      expect(
        _detect(
          detector,
          _pointingHand(openOtherFingerIndexes: const {1, 2, 3}),
        ),
        HandMoveDirection.none,
      );
    });

    test('legacy fingertip movement does not create a direction command', () {
      final invalidPose = _pointingHand(
        indexVector: const Offset(0, -90),
        openOtherFingerIndexes: const {1, 2, 3},
      );

      for (var frame = 0; frame < 8; frame++) {
        expect(_detect(detector, invalidPose), HandMoveDirection.none);
      }
    });
  });

  group('DirectionGestureDetector zoom-in conflict', () {
    late DirectionGestureDetector detector;

    setUp(() {
      detector = DirectionGestureDetector();
    });

    for (final angle in const [0.0, 5.0, 44.0]) {
      test('reserves a $angle degree forward opening for zoom in', () {
        final landmarks =
            angle <= 5
                ? _quadrant4ParallelZoomConflictLandmarks(angle)
                : _horizontalZoomConflictLandmarks(
                  180 - angle,
                  intersection: const Offset(320, 205),
                );
        final hand = _pointingHand(
          indexVector: angle <= 5 ? const Offset(0, -90) : const Offset(-90, 0),
          includeThumb: true,
          landmarkOverrides: landmarks,
        );

        expect(_detect(detector, hand), HandMoveDirection.none);
        expect(detector.debugSummary, contains('zoom-in thumb/index'));
      });
    }

    for (final angle in const [91.0, 110.0]) {
      test('reserves a $angle degree opening for zoom in', () {
        final hand = _pointingHand(
          indexVector: const Offset(-90, 0),
          includeThumb: true,
          landmarkOverrides: _horizontalZoomConflictLandmarks(
            180 - angle,
            intersection: const Offset(320, 205),
          ),
        );

        expect(_detect(detector, hand), HandMoveDirection.none);
        expect(detector.debugSummary, contains('zoom-in thumb/index'));
      });
    }

    test('does not reserve a back-side opening for zoom in', () {
      final hand = _pointingHand(
        indexVector: const Offset(-90, 0),
        includeThumb: true,
        landmarkOverrides: {
          ..._horizontalZoomConflictLandmarks(
            89,
            intersection: const Offset(320, 205),
          ),
          HandLandmarkType.wrist: const Offset(210, 150),
        },
      );

      expect(_confirmMovingLeft(detector, hand), HandMoveDirection.left);
      expect(detector.debugSummary, isNot(contains('zoom-in thumb/index')));
    });

    test('allows direction when the 180 degree rays are parallel', () {
      final hand = _pointingHand(
        includeThumb: true,
        landmarkOverrides: _horizontalZoomConflictLandmarks(180),
      );

      expect(_confirmMovingRight(detector, hand), HandMoveDirection.right);
      expect(detector.debugSummary, isNot(contains('zoom-in thumb/index')));
    });

    test('allows direction when same-facing parallel rays are too close', () {
      final hand = _pointingHand(
        includeThumb: true,
        landmarkOverrides: _horizontalZoomConflictLandmarks(
          0,
          intersection: const Offset(180, 215),
          rayDistance: 30,
        ),
      );

      expect(_confirmMovingRight(detector, hand), HandMoveDirection.right);
      expect(detector.debugSummary, isNot(contains('zoom-in thumb/index')));
    });

    test('allows direction when right-hand rays meet outside quadrant 4', () {
      final hand = _pointingHand(
        includeThumb: true,
        landmarkOverrides: _horizontalZoomConflictLandmarks(
          45,
          intersection: const Offset(180, 205),
        ),
      );

      expect(_confirmMovingRight(detector, hand), HandMoveDirection.right);
      expect(detector.debugSummary, isNot(contains('zoom-in thumb/index')));
    });

    test('reserves a forward intersection beyond two hand sizes', () {
      final hand = _pointingHand(
        indexVector: const Offset(-90, 0),
        includeThumb: true,
        landmarkOverrides: _horizontalZoomConflictLandmarks(
          174,
          intersection: const Offset(1000, 205),
          rayDistance: 800,
        ),
      );

      expect(_detect(detector, hand), HandMoveDirection.none);
      expect(detector.debugSummary, contains('zoom-in thumb/index'));
    });

    test('cancels direction at the exact 2% vertical gap', () {
      final hand = _pointingHand(
        indexPoints: _indexPointsWithDistalAngle(const Offset(-90, 0), 169),
        includeThumb: true,
        landmarkOverrides: _horizontalZoomConflictLandmarks(
          120,
          intersection: const Offset(320, 205),
          segmentLength: 2,
          rayDistance: 1 + 4 / math.sin(math.pi / 3),
        ),
      );

      expect(_detect(detector, hand), HandMoveDirection.none);
      expect(detector.debugSummary, contains('angle=60.0deg'));
    });

    test('does not cancel direction below the 2% vertical gap', () {
      final hand = _pointingHand(
        indexPoints: _indexPointsWithDistalAngle(const Offset(-90, 0), 169),
        includeThumb: true,
        landmarkOverrides: _horizontalZoomConflictLandmarks(
          120,
          intersection: const Offset(320, 205),
          segmentLength: 2,
          rayDistance: 1 + 3.9 / math.sin(math.pi / 3),
        ),
      );

      expect(_confirmMovingLeft(detector, hand), HandMoveDirection.left);
      expect(detector.debugSummary, isNot(contains('zoom-in thumb/index')));
    });

    test('reserves the former 45 degree lower boundary for zoom in', () {
      final hand = _pointingHand(
        indexPoints: _indexPointsWithDistalAngle(const Offset(-90, 0), 169),
        includeThumb: true,
        landmarkOverrides: _horizontalZoomConflictLandmarks(
          135,
          intersection: const Offset(320, 205),
        ),
      );

      expect(_detect(detector, hand), HandMoveDirection.none);
      expect(detector.debugSummary, contains('angle=45.0deg'));
    });

    test('axis intersection does not reserve a 90 degree zoom pose', () {
      final hand = _pointingHand(
        indexVector: const Offset(0, -90),
        indexPoints: _indexPointsWithDistalAngle(const Offset(0, -90), 169),
        includeThumb: true,
        landmarkOverrides: _verticalUpZoomConflictLandmarks,
      );

      expect(_detect(detector, hand), HandMoveDirection.none);
      expect(detector.debugSummary, isNot(contains('zoom-in thumb/index')));
    });

    test('axis intersection leaves a 170 degree pose available for up', () {
      final hand = _pointingHand(
        indexVector: const Offset(0, -90),
        indexPoints: _indexPointsWithDistalAngle(const Offset(0, -90), 170),
        includeThumb: true,
        landmarkOverrides: _verticalUpZoomConflictLandmarks,
      );

      expect(_confirmMovingUp(detector, hand), HandMoveDirection.up);
      expect(detector.debugSummary, isNot(contains('zoom-in thumb/index')));
    });

    test('does not reserve close thumb and index tips for zoom in', () {
      final hand = _pointingHand(
        indexPoints: _indexPointsWithDistalAngle(const Offset(90, 0), 169),
        includeThumb: true,
        landmarkOverrides: _horizontalZoomConflictLandmarks(
          45,
          intersection: const Offset(260, 205),
          segmentLength: 1,
          rayDistance: 0.5 + 4 / math.sin(math.pi / 4),
        ),
      );

      expect(_detect(detector, hand), HandMoveDirection.none);
      expect(detector.debugSummary, isNot(contains('zoom-in thumb/index')));
    });

    test('does not cancel package pointingUp when other fingers are open', () {
      final hand = _pointingHand(
        indexVector: const Offset(0, -90),
        includeThumb: true,
        openOtherFingerIndexes: const {1, 2, 3},
        landmarkOverrides: _verticalUpZoomConflictLandmarks,
        gesture: const GestureResult(
          type: GestureType.pointingUp,
          confidence: 1,
        ),
      );

      expect(_confirmMovingUp(detector, hand), HandMoveDirection.up);
      expect(detector.debugSummary, contains('package pointingUp'));
    });
  });

  group('DirectionGestureDetector depth-aware palm extension', () {
    late DirectionGestureDetector detector;

    setUp(() {
      detector = DirectionGestureDetector();
    });

    test('uses the 10 percent minimum when the tip is closer', () {
      expect(
        _confirmMovingRight(
          detector,
          _pointingHand(
            indexVector: const Offset(16, 0),
            indexDepthVector: -300,
          ),
        ),
        HandMoveDirection.right,
      );
    });

    test('uses the 15 percent maximum when the tip is farther away', () {
      final tooShort = _pointingHand(
        indexVector: const Offset(16, 0),
        indexDepthVector: 300,
      );

      for (var frame = 0; frame < 4; frame += 1) {
        expect(_detect(detector, tooShort), HandMoveDirection.none);
      }
      expect(detector.debugSummary, contains('15.0%'));

      detector.clearState();

      expect(
        _confirmMovingRight(
          detector,
          _pointingHand(
            indexVector: const Offset(18, 0),
            indexDepthVector: 300,
          ),
        ),
        HandMoveDirection.right,
      );
    });

    test('interpolates the requirement between 10 and 15 percent', () {
      final tooShort = _pointingHand(
        indexVector: const Offset(16, 0),
        indexDepthVector: 5.34,
      );

      expect(_detect(detector, tooShort), HandMoveDirection.none);
      expect(detector.debugSummary, contains('12.5%'));

      detector.clearState();

      expect(
        _confirmMovingRight(
          detector,
          _pointingHand(
            indexVector: const Offset(17, 0),
            indexDepthVector: 5.34,
          ),
        ),
        HandMoveDirection.right,
      );
    });

    test('uses palm-relative depth instead of whole-hand depth', () {
      expect(
        _confirmMovingRight(
          detector,
          _pointingHand(
            indexVector: const Offset(16, 0),
            indexDepthVector: -300,
            baseDepth: 900,
          ),
        ),
        HandMoveDirection.right,
      );
    });
  });

  group('DirectionGestureDetector stability and validation', () {
    late DirectionGestureDetector detector;

    setUp(() {
      detector = DirectionGestureDetector();
    });

    for (final testCase in const [
      (Offset(-90, 0), HandMoveDirection.left),
      (Offset(90, 0), HandMoveDirection.right),
      (Offset(0, -90), HandMoveDirection.up),
      (Offset(0, 90), HandMoveDirection.down),
    ]) {
      test('does not count ${testCase.$2.name} while the hand moves', () {
        for (final x in const [0.0, 10.0, 20.0, 30.0, 40.0]) {
          expect(
            _detect(
              detector,
              _pointingHand(indexVector: testCase.$1, handOffset: Offset(x, 0)),
            ),
            HandMoveDirection.none,
          );
        }
        expect(detector.debugSummary, contains('hand moving'));

        final settledHand = _pointingHand(
          indexVector: testCase.$1,
          handOffset: const Offset(40, 0),
        );
        expect(_detect(detector, settledHand), HandMoveDirection.none);
        expect(_detect(detector, settledHand), HandMoveDirection.none);
        expect(_detect(detector, settledHand), testCase.$2);
      });
    }

    test('cancels an active direction as soon as the hand moves', () {
      final hand = _pointingHand(indexVector: const Offset(90, 0));
      expect(_confirmMovingRight(detector, hand), HandMoveDirection.right);

      expect(
        _detect(
          detector,
          _pointingHand(
            indexVector: const Offset(90, 0),
            handOffset: const Offset(10, 0),
          ),
        ),
        HandMoveDirection.none,
      );
      expect(detector.debugSummary, contains('hand moving'));
    });

    test('allows small hand-box jitter inside the three percent radius', () {
      expect(
        _detect(
          detector,
          _pointingHand(
            indexVector: const Offset(90, 0),
            handOffset: Offset.zero,
          ),
        ),
        HandMoveDirection.none,
      );
      expect(
        _detect(
          detector,
          _pointingHand(
            indexVector: const Offset(90, 0),
            handOffset: const Offset(2, 0),
          ),
        ),
        HandMoveDirection.none,
      );
      expect(
        _detect(
          detector,
          _pointingHand(
            indexVector: const Offset(90, 0),
            handOffset: const Offset(4, 0),
          ),
        ),
        HandMoveDirection.right,
      );
    });

    test('exposes candidate and accepted direction for debug drawing', () {
      final hand = _pointingHand(indexVector: const Offset(90, 0));

      expect(_detect(detector, hand), HandMoveDirection.none);
      expect(detector.debugCandidateDirection, HandMoveDirection.right);
      expect(detector.debugAcceptedDirection, HandMoveDirection.none);

      expect(_detect(detector, hand), HandMoveDirection.none);
      expect(_detect(detector, hand), HandMoveDirection.right);
      expect(detector.debugCandidateDirection, HandMoveDirection.right);
      expect(detector.debugAcceptedDirection, HandMoveDirection.right);
    });

    test('keeps right inside its 305 to 70 degree screen sector', () {
      expect(
        _confirmMovingRight(
          detector,
          _pointingHand(indexVector: _vectorAtDegrees(40)),
        ),
        HandMoveDirection.right,
      );

      expect(
        _detect(detector, _pointingHand(indexVector: _vectorAtDegrees(50))),
        HandMoveDirection.right,
      );
      expect(detector.debugSummary, contains('static right'));

      expect(
        _detect(detector, _pointingHand(indexVector: _vectorAtDegrees(56))),
        HandMoveDirection.none,
      );
    });

    test('exact upper-right diagonal uses right three-frame confirmation', () {
      expect(
        _confirmMovingUp(
          detector,
          _pointingHand(indexVector: const Offset(0, -90)),
        ),
        HandMoveDirection.up,
      );

      expect(
        _detect(detector, _pointingHand(indexVector: const Offset(90, -90))),
        HandMoveDirection.none,
      );
      expect(
        _detect(detector, _pointingHand(indexVector: const Offset(90, -90))),
        HandMoveDirection.none,
      );
      expect(
        _detect(detector, _pointingHand(indexVector: const Offset(90, -90))),
        HandMoveDirection.right,
      );
    });

    test('losing the pose restarts right confirmation', () {
      expect(
        _confirmMovingRight(
          detector,
          _pointingHand(indexVector: _vectorAtDegrees(40)),
        ),
        HandMoveDirection.right,
      );

      expect(
        _detect(
          detector,
          _pointingHand(openOtherFingerIndexes: const {1, 2, 3}),
        ),
        HandMoveDirection.none,
      );

      expect(
        _detect(detector, _pointingHand(indexVector: _vectorAtDegrees(50))),
        HandMoveDirection.none,
      );
      expect(detector.debugSummary, contains('1/3'));
    });

    test('clearState restarts right confirmation', () {
      expect(
        _confirmMovingRight(
          detector,
          _pointingHand(indexVector: _vectorAtDegrees(40)),
        ),
        HandMoveDirection.right,
      );

      detector.clearState(reason: 'test reset');

      expect(
        _detect(detector, _pointingHand(indexVector: _vectorAtDegrees(50))),
        HandMoveDirection.none,
      );
      expect(detector.debugSummary, contains('1/3'));
    });

    test('rejects low-confidence hands', () {
      expect(
        _detect(detector, _pointingHand(score: 0.2)),
        HandMoveDirection.none,
      );
      expect(detector.debugSummary, contains('invalid frame'));
    });

    test('rejects non-finite image sizes', () {
      expect(
        _detect(
          detector,
          _pointingHand(),
          imageSize: const Size(double.nan, 400),
        ),
        HandMoveDirection.none,
      );
    });

    test('rejects missing or low-visibility index landmarks', () {
      expect(
        _detect(
          detector,
          _pointingHand(missingTypes: const {HandLandmarkType.indexFingerDIP}),
        ),
        HandMoveDirection.none,
      );

      expect(
        _detect(
          detector,
          _pointingHand(
            lowVisibilityTypes: const {HandLandmarkType.indexFingerTip},
          ),
        ),
        HandMoveDirection.none,
      );
    });
  });
}

HandMoveDirection _detect(
  DirectionGestureDetector detector,
  Hand hand, {
  Size imageSize = _imageSize,
  bool mirrorHorizontally = false,
}) {
  return detector.detect(
    hand: hand,
    imageSize: imageSize,
    mirrorHorizontally: mirrorHorizontally,
  );
}

HandMoveDirection _confirmMovingLeft(
  DirectionGestureDetector detector,
  Hand hand, {
  bool mirrorHorizontally = false,
}) {
  var result = HandMoveDirection.none;
  for (
    var frame = 1;
    frame <= HandGestureThresholds.movingLeftRequiredConsecutiveFrames;
    frame += 1
  ) {
    result = _detect(detector, hand, mirrorHorizontally: mirrorHorizontally);
    if (frame < HandGestureThresholds.movingLeftRequiredConsecutiveFrames) {
      expect(result, HandMoveDirection.none);
    }
  }
  return result;
}

HandMoveDirection _confirmMovingRight(
  DirectionGestureDetector detector,
  Hand hand, {
  Size imageSize = _imageSize,
  bool mirrorHorizontally = false,
}) {
  var result = HandMoveDirection.none;
  for (
    var frame = 1;
    frame <= HandGestureThresholds.movingRightRequiredConsecutiveFrames;
    frame += 1
  ) {
    result = _detect(
      detector,
      hand,
      imageSize: imageSize,
      mirrorHorizontally: mirrorHorizontally,
    );
    if (frame < HandGestureThresholds.movingRightRequiredConsecutiveFrames) {
      expect(result, HandMoveDirection.none);
    }
  }
  return result;
}

HandMoveDirection _confirmMovingUp(
  DirectionGestureDetector detector,
  Hand hand, {
  Size imageSize = _imageSize,
  bool mirrorHorizontally = false,
}) {
  var result = HandMoveDirection.none;
  for (
    var frame = 1;
    frame <= HandGestureThresholds.directionRequiredSteadyFrames;
    frame += 1
  ) {
    result = _detect(
      detector,
      hand,
      imageSize: imageSize,
      mirrorHorizontally: mirrorHorizontally,
    );
  }
  return result;
}

HandMoveDirection _confirmMovingDown(
  DirectionGestureDetector detector,
  Hand hand, {
  bool mirrorHorizontally = false,
}) {
  var result = HandMoveDirection.none;
  for (
    var frame = 1;
    frame <= HandGestureThresholds.movingDownRequiredConsecutiveFrames;
    frame += 1
  ) {
    result = _detect(detector, hand, mirrorHorizontally: mirrorHorizontally);
    if (frame < HandGestureThresholds.movingDownRequiredConsecutiveFrames) {
      expect(result, HandMoveDirection.none);
    }
  }
  return result;
}

Offset _vectorAtDegrees(double degrees, {double length = 100}) {
  final radians = degrees * math.pi / 180;
  return Offset(math.cos(radians) * length, math.sin(radians) * length);
}

Offset _vectorAtScreenDirectionDegrees(double degrees, {double length = 100}) {
  final radians = degrees * math.pi / 180;
  return Offset(math.cos(radians) * length, -math.sin(radians) * length);
}

Map<HandLandmarkType, Offset> _horizontalZoomConflictLandmarks(
  double angleDegrees, {
  Offset intersection = const Offset(180, 205),
  double segmentLength = 30,
  double rayDistance = 90,
}) {
  final segmentDirection = _vectorAtDegrees(angleDegrees, length: 1);
  return {
    HandLandmarkType.thumbMCP:
        intersection + segmentDirection * (rayDistance - 2 * segmentLength),
    HandLandmarkType.thumbIP:
        intersection + segmentDirection * (rayDistance - segmentLength),
    HandLandmarkType.thumbTip: intersection + segmentDirection * rayDistance,
  };
}

Map<HandLandmarkType, Offset> _quadrant4ParallelZoomConflictLandmarks(
  double angleDegrees,
) {
  const thumbTip = Offset(120, 180);
  const thumbRay = Offset(30, 30);
  const indexTip = Offset(210, 100);
  final indexRayAngle = (45 + angleDegrees) * math.pi / 180;
  final indexRay =
      Offset(math.cos(indexRayAngle), math.sin(indexRayAngle)) *
      thumbRay.distance;

  return {
    HandLandmarkType.thumbIP: thumbTip + thumbRay,
    HandLandmarkType.thumbTip: thumbTip,
    HandLandmarkType.indexFingerDIP: indexTip + indexRay,
    HandLandmarkType.indexFingerTip: indexTip,
  };
}

Hand _pointingHand({
  Offset indexVector = const Offset(90, 0),
  List<Offset>? indexPoints,
  double indexDepthVector = 0,
  double baseDepth = 0,
  Set<int> openOtherFingerIndexes = const {},
  double otherFingerRotationDegrees = 0,
  Map<HandLandmarkType, Offset> landmarkOverrides = const {},
  Set<HandLandmarkType> missingTypes = const {},
  Set<HandLandmarkType> lowVisibilityTypes = const {},
  Map<HandLandmarkType, double> landmarkDepthOverrides = const {},
  bool includeThumb = false,
  Offset thumbTip = const Offset(195, 225),
  Offset handOffset = Offset.zero,
  double score = 1,
  Handedness handedness = Handedness.right,
  GestureResult? gesture,
}) {
  final landmarks = <HandLandmark>[];

  void addLandmark(HandLandmarkType type, Offset point, {double? z}) {
    if (missingTypes.contains(type)) return;

    final resolvedPoint = (landmarkOverrides[type] ?? point) + handOffset;

    landmarks.add(
      HandLandmark(
        type: type,
        x: resolvedPoint.dx,
        y: resolvedPoint.dy,
        z: landmarkDepthOverrides[type] ?? z ?? baseDepth,
        visibility: lowVisibilityTypes.contains(type) ? 0.2 : 1,
      ),
    );
  }

  addLandmark(HandLandmarkType.wrist, const Offset(210, 285));
  if (includeThumb) {
    addLandmark(HandLandmarkType.thumbMCP, const Offset(180, 235));
    addLandmark(HandLandmarkType.thumbIP, const Offset(165, 230));
    addLandmark(HandLandmarkType.thumbTip, thumbTip);
  }

  final resolvedIndexPoints =
      indexPoints ?? _straightChainPoints(_indexBase, indexVector);
  for (
    var pointIndex = 0;
    pointIndex < _fingerChains.first.length;
    pointIndex++
  ) {
    addLandmark(
      _fingerChains.first[pointIndex],
      resolvedIndexPoints[pointIndex],
      z: baseDepth + indexDepthVector * pointIndex / 3,
    );
  }

  final otherFingerBases = [
    const Offset(190, 225),
    const Offset(215, 225),
    const Offset(240, 220),
  ];

  for (var fingerIndex = 1; fingerIndex < _fingerChains.length; fingerIndex++) {
    final base = otherFingerBases[fingerIndex - 1];
    final points =
        openOtherFingerIndexes.contains(fingerIndex)
            ? _straightChainPoints(base, const Offset(0, -75))
            : _foldedChainPoints(
              base,
              rotationDegrees: otherFingerRotationDegrees,
            );

    for (var pointIndex = 0; pointIndex < points.length; pointIndex++) {
      addLandmark(_fingerChains[fingerIndex][pointIndex], points[pointIndex]);
    }
  }

  return Hand(
    boundingBox: BoundingBox.ltrb(
      100 + handOffset.dx,
      100 + handOffset.dy,
      300 + handOffset.dx,
      300 + handOffset.dy,
    ),
    score: score,
    landmarks: landmarks,
    imageWidth: _imageSize.width.toInt(),
    imageHeight: _imageSize.height.toInt(),
    handedness: handedness,
    gesture: gesture,
  );
}

List<Offset> _straightChainPoints(Offset base, Offset vector) {
  return [base, base + vector * 0.35, base + vector * 0.70, base + vector];
}

List<Offset> _indexPointsWithDistalAngle(Offset vector, double angleDegrees) {
  final dip = _indexBase + vector * 0.70;
  final tip = _indexBase + vector;
  final segmentLength = vector.distance * 0.35;
  final tipSegmentAngle = math.atan2(vector.dy, vector.dx);
  final pipRayAngle = tipSegmentAngle + angleDegrees * math.pi / 180;
  final pip =
      dip +
      Offset(math.cos(pipRayAngle), math.sin(pipRayAngle)) * segmentLength;

  return [_indexBase, pip, dip, tip];
}

List<Offset> _moderatelyBentIndexPoints(double screenDirectionDegrees) {
  const segmentLength = 30.0;
  final coordinateDirectionDegrees = -screenDirectionDegrees;

  Offset segmentAt(double degrees) {
    final radians = degrees * math.pi / 180;
    return Offset(
      math.cos(radians) * segmentLength,
      math.sin(radians) * segmentLength,
    );
  }

  final first = _indexBase + segmentAt(coordinateDirectionDegrees - 30);
  final second = first + segmentAt(coordinateDirectionDegrees);
  final tip = second + segmentAt(coordinateDirectionDegrees + 30);
  return [_indexBase, first, second, tip];
}

List<Offset> _foldedChainPoints(Offset base, {double rotationDegrees = 0}) {
  final radians = rotationDegrees * math.pi / 180;

  Offset rotate(Offset vector) => Offset(
    vector.dx * math.cos(radians) - vector.dy * math.sin(radians),
    vector.dx * math.sin(radians) + vector.dy * math.cos(radians),
  );

  return [
    base,
    base + rotate(const Offset(0, -30)),
    base + rotate(const Offset(8, -18)),
    base + rotate(const Offset(6, -5)),
  ];
}

Map<HandLandmarkType, Offset> _compactOtherFingerOverrides() {
  final overrides = <HandLandmarkType, Offset>{};
  final bases = [
    const Offset(190, 225),
    const Offset(215, 225),
    const Offset(240, 220),
  ];
  final vectors = [
    const Offset(15, -45),
    const Offset(-4, -52),
    const Offset(-29, -47),
  ];
  for (var fingerIndex = 1; fingerIndex < _fingerChains.length; fingerIndex++) {
    final points = _straightChainPoints(
      bases[fingerIndex - 1],
      vectors[fingerIndex - 1],
    );
    for (var pointIndex = 0; pointIndex < points.length; pointIndex++) {
      overrides[_fingerChains[fingerIndex][pointIndex]] = points[pointIndex];
    }
  }
  return overrides;
}

Map<HandLandmarkType, Offset> _fingerJointOverrides(
  List<HandLandmarkType> chain,
  Offset mcp,
  double jointAngleDegrees,
) {
  final pip = mcp + const Offset(0, -30);
  final distalRadians = (90 + jointAngleDegrees) * math.pi / 180;
  final distalVector = Offset(
    math.cos(distalRadians) * 20,
    math.sin(distalRadians) * 20,
  );
  final dip = pip + distalVector;
  final tip = dip + distalVector;

  return {chain[0]: mcp, chain[1]: pip, chain[2]: dip, chain[3]: tip};
}

Map<HandLandmarkType, Offset> _compressedFingerOverrides(
  List<HandLandmarkType> chain,
  Offset mcp, {
  Offset? tip,
}) {
  return {
    chain[0]: mcp,
    chain[1]: mcp + const Offset(0, -30),
    chain[2]: mcp + const Offset(0, -60),
    chain[3]: tip ?? mcp + const Offset(0, -5),
  };
}
