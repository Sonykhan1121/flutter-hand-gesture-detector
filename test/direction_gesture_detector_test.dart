import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gesture_detector/hand_gesture_features/domain/constants/hand_gesture_thresholds.dart';
import 'package:gesture_detector/hand_gesture_features/domain/enums/hand_move_direction.dart';
import 'package:gesture_detector/hand_gesture_features/domain/services/direction_gesture_detector.dart';
import 'package:hand_detection/hand_detection.dart';

const _imageSize = Size(400, 400);
const _indexBase = Offset(200, 205);

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
          _ => _detect(detector, hand),
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
          _ => _detect(detector, hand),
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
        _detect(
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
        openOtherFingerIndexes: const {1},
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

    test('requires both folded angle and palm-distance checks', () {
      final openMiddle = _pointingHand(
        indexVector: const Offset(-90, 0),
        openOtherFingerIndexes: const {1},
      );
      expect(_detect(detector, openMiddle), HandMoveDirection.none);
      expect(detector.debugSummary, contains('middle finger not folded'));

      final distantMiddleTip = _pointingHand(
        indexVector: const Offset(-90, 0),
        landmarkOverrides: const {
          HandLandmarkType.middleFingerTip: Offset(350, 50),
        },
      );
      expect(_detect(detector, distantMiddleTip), HandMoveDirection.none);
      expect(detector.debugSummary, contains('middle finger not folded'));
    });

    test('requires every specified point 0 and 5-20 to be reliable', () {
      final hand = _pointingHand(
        indexVector: const Offset(-90, 0),
        lowVisibilityTypes: const {HandLandmarkType.ringFingerDIP},
      );

      expect(_detect(detector, hand), HandMoveDirection.none);
      expect(detector.debugSummary, contains('missing required point'));
    });
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
        openOtherFingerIndexes: const {1},
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

    test('rejects either index joint below 145 degrees', () {
      final indexPoints = [
        _indexBase,
        _indexBase + const Offset(30, 0),
        _indexBase + const Offset(50, 20),
        _indexBase + const Offset(90, 20),
      ];

      for (var frame = 0; frame < 4; frame += 1) {
        expect(
          _detect(detector, _pointingHand(indexPoints: indexPoints)),
          HandMoveDirection.none,
        );
      }
      expect(detector.debugSummary, contains('index joints'));
    });

    test('rejects an index tip that is not clearly right of the palm', () {
      final hand = _pointingHand(
        indexVector: const Offset(90, 0),
        landmarkOverrides: const {HandLandmarkType.wrist: Offset(1000, 285)},
      );

      expect(_detect(detector, hand), HandMoveDirection.none);
      expect(detector.debugSummary, contains('tip not clearly right'));
    });

    test('requires both folded angle and palm-distance checks', () {
      final openMiddle = _pointingHand(
        indexVector: const Offset(90, 0),
        openOtherFingerIndexes: const {1},
      );
      expect(_detect(detector, openMiddle), HandMoveDirection.none);
      expect(detector.debugSummary, contains('middle finger not folded'));

      final distantMiddleTip = _pointingHand(
        indexVector: const Offset(90, 0),
        landmarkOverrides: const {
          HandLandmarkType.middleFingerTip: Offset(350, 50),
        },
      );
      expect(_detect(detector, distantMiddleTip), HandMoveDirection.none);
      expect(detector.debugSummary, contains('middle finger not folded'));
    });

    test('requires every specified point 0 and 5-20 to be reliable', () {
      final hand = _pointingHand(
        indexVector: const Offset(90, 0),
        lowVisibilityTypes: const {HandLandmarkType.ringFingerDIP},
      );

      expect(_detect(detector, hand), HandMoveDirection.none);
      expect(detector.debugSummary, contains('missing required point'));
    });

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
  });

  group('DirectionGestureDetector Moving Up 21-landmark replacement', () {
    late DirectionGestureDetector detector;

    setUp(() {
      detector = DirectionGestureDetector();
    });

    test('triggers immediately on the first matching frame', () {
      final hand = _pointingHand(indexVector: const Offset(0, -90));

      expect(_detect(detector, hand), HandMoveDirection.up);
      expect(_detect(detector, hand), HandMoveDirection.up);
    });

    for (final angle in const [75.0, 90.0, 120.0]) {
      test('accepts the exact initial $angle degree screen direction', () {
        final hand = _pointingHand(
          indexVector: _vectorAtScreenDirectionDegrees(angle),
        );

        expect(_detect(detector, hand), HandMoveDirection.up);
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
        _detect(detector, _pointingHand(indexVector: const Offset(0, -90))),
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
        _detect(detector, _pointingHand(indexVector: const Offset(0, -90))),
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
          _detect(
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
        _detect(
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
        _detect(
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
        _detect(
          detector,
          _pointingHand(indexVector: const Offset(0, -90)),
          mirrorHorizontally: true,
        ),
        HandMoveDirection.up,
      );
    });

    test('rejects either index joint below 135 degrees', () {
      final indexPoints = [
        _indexBase,
        _indexBase + const Offset(0, -30),
        _indexBase + const Offset(20, -50),
        _indexBase + const Offset(0, -90),
      ];

      expect(
        _detect(detector, _pointingHand(indexPoints: indexPoints)),
        HandMoveDirection.none,
      );
      expect(detector.debugSummary, contains('index joints'));
    });

    test('accepts a moderate bend while points 5-8 rise near the y-axis', () {
      final indexPoints = [
        _indexBase,
        _indexBase + const Offset(25, -25),
        _indexBase + const Offset(25, -60),
        _indexBase + const Offset(20, -95),
      ];

      expect(
        _detect(detector, _pointingHand(indexPoints: indexPoints)),
        HandMoveDirection.up,
      );
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

    test('requires both folded angle and palm-distance checks', () {
      final openMiddle = _pointingHand(
        indexVector: const Offset(0, -90),
        openOtherFingerIndexes: const {1},
      );
      expect(_detect(detector, openMiddle), HandMoveDirection.none);
      expect(detector.debugSummary, contains('middle finger not folded'));

      final distantMiddleTip = _pointingHand(
        indexVector: const Offset(0, -90),
        landmarkOverrides: const {
          HandLandmarkType.middleFingerTip: Offset(350, 50),
        },
      );
      expect(_detect(detector, distantMiddleTip), HandMoveDirection.none);
      expect(detector.debugSummary, contains('middle finger not folded'));
    });

    test('requires every specified point 5-20 to be reliable', () {
      final hand = _pointingHand(
        indexVector: const Offset(0, -90),
        lowVisibilityTypes: const {HandLandmarkType.ringFingerDIP},
      );

      expect(_detect(detector, hand), HandMoveDirection.none);
      expect(detector.debugSummary, contains('missing required point 5-20'));
    });

    test('ignores missing and extended thumb landmarks', () {
      expect(
        _detect(
          detector,
          _pointingHand(indexVector: const Offset(0, -90), includeThumb: false),
        ),
        HandMoveDirection.up,
      );

      detector.clearState();

      expect(
        _detect(
          detector,
          _pointingHand(
            indexVector: const Offset(0, -90),
            includeThumb: true,
            thumbTip: const Offset(105, 155),
          ),
        ),
        HandMoveDirection.up,
      );
    });
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
        openOtherFingerIndexes: const {1},
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

    test('requires both folded angle and palm-distance checks', () {
      final openMiddle = _pointingHand(
        indexVector: const Offset(0, 90),
        openOtherFingerIndexes: const {1},
      );
      expect(_detect(detector, openMiddle), HandMoveDirection.none);
      expect(detector.debugSummary, contains('middle finger not folded'));

      final distantMiddleTip = _pointingHand(
        indexVector: const Offset(0, 90),
        landmarkOverrides: const {
          HandLandmarkType.middleFingerTip: Offset(350, 50),
        },
      );
      expect(_detect(detector, distantMiddleTip), HandMoveDirection.none);
      expect(detector.debugSummary, contains('middle finger not folded'));
    });

    test('ignores point 5 but requires points 6-8 and 9-20', () {
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

      final hand = _pointingHand(
        indexVector: const Offset(0, 90),
        lowVisibilityTypes: const {HandLandmarkType.ringFingerDIP},
      );

      expect(_detect(detector, hand), HandMoveDirection.none);
      expect(detector.debugSummary, contains('missing required point'));
    });

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
      (0.0, HandMoveDirection.right),
      (90.0, HandMoveDirection.up),
      (180.0, HandMoveDirection.left),
      (270.0, HandMoveDirection.down),
    ]) {
      test(
        'accepts an approximately 150 degree index for ${testCase.$2.name}',
        () {
          final hand = _pointingHand(
            indexPoints: _moderatelyBentIndexPoints(testCase.$1),
          );
          final result = switch (testCase.$2) {
            HandMoveDirection.left => _confirmMovingLeft(detector, hand),
            HandMoveDirection.right => _confirmMovingRight(detector, hand),
            HandMoveDirection.down => _confirmMovingDown(detector, hand),
            _ => _detect(detector, hand),
          };

          expect(result, testCase.$2);
        },
      );
    }

    test('moving right rejects an index bent to approximately 138 degrees', () {
      final indexPoints = [
        _indexBase,
        _indexBase + const Offset(30, 0),
        _indexBase + const Offset(52, 20),
        _indexBase + const Offset(75, 40),
      ];

      expect(
        _detect(detector, _pointingHand(indexPoints: indexPoints)),
        HandMoveDirection.none,
      );
      expect(detector.debugSummary, contains('index joints'));
    });

    test('does not use an easier bend rule for moving right', () {
      final indexPoints = [
        _indexBase,
        _indexBase + const Offset(30, 0),
        _indexBase + const Offset(45, 26),
        _indexBase + const Offset(60, 52),
      ];

      expect(
        _detect(detector, _pointingHand(indexPoints: indexPoints)),
        HandMoveDirection.none,
      );
      expect(detector.debugSummary, contains('index joints'));
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
      expect(detector.debugSummary, contains('index joints'));
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
      test('rejects pose when finger $fingerIndex is open', () {
        expect(
          _detect(
            detector,
            _pointingHand(openOtherFingerIndexes: {fingerIndex}),
          ),
          HandMoveDirection.none,
        );
        expect(detector.debugSummary, contains('finger not folded'));
      });
    }

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
      expect(detector.debugSummary, contains('index joints'));
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
          _ => _detect(detector, hand),
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

      expect(_detect(detector, hand), HandMoveDirection.up);
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

    for (final angle in const [0.0, 44.0, 91.0, 180.0]) {
      test('does not cancel direction at $angle degrees', () {
        const thumbMid = Offset(200, 240);
        final thumbVector = _vectorAtDegrees(angle, length: 60);
        final hand = _pointingHand(
          includeThumb: true,
          landmarkOverrides: {
            HandLandmarkType.thumbMCP: thumbMid - thumbVector,
            HandLandmarkType.thumbIP: thumbMid - thumbVector * 0.5,
            HandLandmarkType.thumbTip: thumbMid + thumbVector * 0.5,
          },
        );

        expect(_confirmMovingRight(detector, hand), HandMoveDirection.right);
        expect(detector.debugSummary, isNot(contains('zoom-in thumb/index')));
      });
    }

    test('cancels direction at the exact 2% vertical gap', () {
      const thumbMid = Offset(200, 209);
      final thumbVector = _vectorAtDegrees(60, length: 60);
      final hand = _pointingHand(
        includeThumb: true,
        landmarkOverrides: {
          HandLandmarkType.thumbMCP: thumbMid - thumbVector,
          HandLandmarkType.thumbIP: thumbMid - thumbVector * 0.5,
          HandLandmarkType.thumbTip: thumbMid + thumbVector * 0.5,
        },
      );

      expect(_detect(detector, hand), HandMoveDirection.none);
      expect(detector.debugSummary, contains('angle=60.0deg'));
    });

    test('does not cancel direction below the 2% vertical gap', () {
      const thumbMid = Offset(200, 208.9);
      final thumbVector = _vectorAtDegrees(60, length: 60);
      final hand = _pointingHand(
        includeThumb: true,
        landmarkOverrides: {
          HandLandmarkType.thumbMCP: thumbMid - thumbVector,
          HandLandmarkType.thumbIP: thumbMid - thumbVector * 0.5,
          HandLandmarkType.thumbTip: thumbMid + thumbVector * 0.5,
        },
      );

      expect(_confirmMovingRight(detector, hand), HandMoveDirection.right);
      expect(detector.debugSummary, isNot(contains('zoom-in thumb/index')));
    });

    test('cancels direction at the 45 degree lower boundary', () {
      final hand = _pointingHand(
        includeThumb: true,
        landmarkOverrides: const {
          HandLandmarkType.thumbMCP: Offset(140, 180),
          HandLandmarkType.thumbIP: Offset(170, 210),
          HandLandmarkType.thumbTip: Offset(230, 270),
        },
      );

      expect(_detect(detector, hand), HandMoveDirection.none);
      expect(detector.debugSummary, contains('angle=45.0deg'));
    });

    test('cancels direction when straight thumb and index are 90 degrees', () {
      final hand = _pointingHand(
        indexVector: const Offset(0, -90),
        includeThumb: true,
        landmarkOverrides: const {
          HandLandmarkType.thumbMCP: Offset(110, 260),
          HandLandmarkType.thumbIP: Offset(155, 260),
          HandLandmarkType.thumbTip: Offset(200, 260),
        },
      );

      expect(_detect(detector, hand), HandMoveDirection.none);
      expect(detector.debugSummary, contains('angle=90.0deg'));
    });

    test('cancels direction even when thumb and index tips are close', () {
      final hand = _pointingHand(
        includeThumb: true,
        landmarkOverrides: const {
          HandLandmarkType.thumbMCP: Offset(200, 295),
          HandLandmarkType.thumbIP: Offset(230, 265),
          HandLandmarkType.thumbTip: Offset(290, 205),
        },
      );

      expect(_detect(detector, hand), HandMoveDirection.none);
      expect(detector.debugSummary, contains('zoom-in thumb/index'));
    });

    test('does not cancel package pointingUp when other fingers are open', () {
      final hand = _pointingHand(
        indexVector: const Offset(0, -90),
        includeThumb: true,
        openOtherFingerIndexes: const {1, 2, 3},
        landmarkOverrides: const {
          HandLandmarkType.thumbMCP: Offset(110, 260),
          HandLandmarkType.thumbIP: Offset(155, 260),
          HandLandmarkType.thumbTip: Offset(200, 260),
        },
        gesture: const GestureResult(
          type: GestureType.pointingUp,
          confidence: 1,
        ),
      );

      expect(_detect(detector, hand), HandMoveDirection.up);
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
        _detect(detector, _pointingHand(indexVector: const Offset(0, -90))),
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
        _detect(detector, _pointingHand(openOtherFingerIndexes: const {1})),
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
  bool mirrorHorizontally = false,
}) {
  var result = HandMoveDirection.none;
  for (
    var frame = 1;
    frame <= HandGestureThresholds.movingRightRequiredConsecutiveFrames;
    frame += 1
  ) {
    result = _detect(detector, hand, mirrorHorizontally: mirrorHorizontally);
    if (frame < HandGestureThresholds.movingRightRequiredConsecutiveFrames) {
      expect(result, HandMoveDirection.none);
    }
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
  bool includeThumb = false,
  Offset thumbTip = const Offset(195, 225),
  double score = 1,
  Handedness handedness = Handedness.right,
  GestureResult? gesture,
}) {
  final landmarks = <HandLandmark>[];

  void addLandmark(HandLandmarkType type, Offset point, {double? z}) {
    if (missingTypes.contains(type)) return;

    final resolvedPoint = landmarkOverrides[type] ?? point;

    landmarks.add(
      HandLandmark(
        type: type,
        x: resolvedPoint.dx,
        y: resolvedPoint.dy,
        z: z ?? baseDepth,
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
    final points = openOtherFingerIndexes.contains(fingerIndex)
        ? _straightChainPoints(base, const Offset(0, -75))
        : _foldedChainPoints(base, rotationDegrees: otherFingerRotationDegrees);

    for (var pointIndex = 0; pointIndex < points.length; pointIndex++) {
      addLandmark(_fingerChains[fingerIndex][pointIndex], points[pointIndex]);
    }
  }

  return Hand(
    boundingBox: BoundingBox.ltrb(100, 100, 300, 300),
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
