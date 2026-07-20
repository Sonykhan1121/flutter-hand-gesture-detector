import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gesture_detector/hand_gesture_features/domain/services/hand_geometry_service.dart';
import 'package:hand_detection/hand_detection.dart';

void main() {
  group('HandGeometryService isReliableHand', () {
    const geometry = HandGeometryService();

    test('accepts hands with landmarks and finite minimum confidence', () {
      expect(geometry.isReliableHand(_handWithLandmark()), isTrue);
    });

    test('rejects hands without landmarks', () {
      expect(geometry.isReliableHand(_handWithoutLandmarks()), isFalse);
    });

    test('rejects hands without any usable visible landmark', () {
      expect(
        geometry.isReliableHand(_handWithLandmark(x: double.nan)),
        isFalse,
      );
      expect(
        geometry.isReliableHand(_handWithLandmark(visibility: 0.2)),
        isFalse,
      );
    });

    test('rejects low and non-finite confidence scores', () {
      expect(geometry.isReliableHand(_handWithLandmark(score: 0.2)), isFalse);
      expect(
        geometry.isReliableHand(_handWithLandmark(score: double.infinity)),
        isFalse,
      );
      expect(
        geometry.isReliableHand(_handWithLandmark(score: double.nan)),
        isFalse,
      );
    });

    test('rejects non-finite or empty bounding boxes', () {
      expect(
        geometry.isReliableHand(
          _handWithLandmark(
            boundingBox: BoundingBox.ltrb(0, 0, double.nan, 100),
          ),
        ),
        isFalse,
      );
      expect(
        geometry.isReliableHand(
          _handWithLandmark(boundingBox: BoundingBox.ltrb(10, 20, 10, 20)),
        ),
        isFalse,
      );
    });

    test('filters only reliable hands', () {
      final reliable = _handWithLandmark(score: 0.9);

      final filtered = geometry.reliableHands([
        _handWithLandmark(score: 0.2),
        _handWithoutLandmarks(),
        _handWithLandmark(score: double.infinity),
        reliable,
      ]);

      expect(filtered, hasLength(1));
      expect(filtered.single, same(reliable));
    });

    test('selects the highest-confidence reliable hand without focus', () {
      final low = _handWithLandmark(score: 0.6);
      final high = _handWithLandmark(score: 0.9);

      expect(
        geometry.bestReliableHand([
          _handWithLandmark(score: double.infinity),
          low,
          high,
        ]),
        same(high),
      );
    });

    test('selects the nearest reliable hand to the focused box', () {
      final near = _handWithLandmark(
        boundingBox: BoundingBox.ltrb(90, 90, 130, 130),
        score: 0.6,
      );
      final far = _handWithLandmark(
        boundingBox: BoundingBox.ltrb(260, 260, 320, 320),
        score: 0.95,
      );

      expect(
        geometry.bestReliableHand([
          _handWithLandmark(
            boundingBox: BoundingBox.ltrb(100, 100, 140, 140),
            score: double.infinity,
          ),
          far,
          near,
        ], focusedHandBox: const Rect.fromLTRB(100, 100, 140, 140)),
        same(near),
      );
    });

    test('returns null when no reliable hand is available', () {
      expect(
        geometry.bestReliableHand([
          _handWithoutLandmarks(),
          _handWithLandmark(score: 0.2),
          _handWithLandmark(score: double.nan),
        ]),
        isNull,
      );
    });
  });

  group('HandGeometryService isReliablePackageGesture', () {
    const geometry = HandGeometryService();

    test('accepts finite package gestures at the confidence threshold', () {
      expect(
        geometry.isReliablePackageGesture(
          const GestureResult(type: GestureType.victory, confidence: 0.5),
          type: GestureType.victory,
        ),
        isTrue,
      );
    });

    test(
      'rejects null, wrong type, low confidence, and non-finite confidence',
      () {
        expect(geometry.isReliablePackageGesture(null), isFalse);
        expect(
          geometry.isReliablePackageGesture(
            const GestureResult(type: GestureType.thumbUp, confidence: 1),
            type: GestureType.victory,
          ),
          isFalse,
        );
        expect(
          geometry.isReliablePackageGesture(
            const GestureResult(type: GestureType.victory, confidence: 0.49),
          ),
          isFalse,
        );
        expect(
          geometry.isReliablePackageGesture(
            const GestureResult(
              type: GestureType.victory,
              confidence: double.infinity,
            ),
          ),
          isFalse,
        );
        expect(
          geometry.isReliablePackageGesture(
            const GestureResult(
              type: GestureType.victory,
              confidence: double.nan,
            ),
          ),
          isFalse,
        );
      },
    );
  });

  group('HandGeometryService visibleLandmark', () {
    const geometry = HandGeometryService();

    test('returns visible landmarks with finite coordinates', () {
      final hand = _handWithLandmark();

      expect(
        geometry.visibleLandmark(hand, HandLandmarkType.indexFingerTip),
        isNotNull,
      );
    });

    test('rejects non-finite coordinates and visibility', () {
      for (final hand in [
        _handWithLandmark(x: double.nan),
        _handWithLandmark(y: double.infinity),
        _handWithLandmark(z: double.negativeInfinity),
        _handWithLandmark(visibility: double.nan),
      ]) {
        expect(
          geometry.visibleLandmark(hand, HandLandmarkType.indexFingerTip),
          isNull,
        );
      }
    });

    test('rejects low-visibility landmarks', () {
      final hand = _handWithLandmark(visibility: 0.2);

      expect(
        geometry.visibleLandmark(hand, HandLandmarkType.indexFingerTip),
        isNull,
      );
    });
  });

  group('HandGeometryService handSizeFromBoundingBox', () {
    const geometry = HandGeometryService();

    test('returns the larger finite bounding-box side', () {
      expect(
        geometry.handSizeFromBoundingBox(BoundingBox.ltrb(10, 20, 110, 260)),
        240,
      );
    });

    test('returns zero for non-finite bounding boxes', () {
      expect(
        geometry.handSizeFromBoundingBox(
          BoundingBox.ltrb(0, 0, double.nan, 100),
        ),
        0,
      );
      expect(
        geometry.handSizeFromBoundingBox(
          BoundingBox.ltrb(0, 0, 100, double.infinity),
        ),
        0,
      );
    });
  });

  group('HandGeometryService forwardRayIntersection2D', () {
    const geometry = HandGeometryService();

    ForwardRayIntersection2D? intersection(
      Offset firstStart,
      Offset firstThrough,
      Offset secondStart,
      Offset secondThrough, {
      double minForwardScale = 1,
      double parallelToleranceDegrees = 5,
      double minParallelLineSeparation = 0,
    }) {
      return geometry.forwardRayIntersection2D(
        firstStart: _landmark(firstStart),
        firstThrough: _landmark(firstThrough),
        secondStart: _landmark(secondStart),
        secondThrough: _landmark(secondThrough),
        minForwardScale: minForwardScale,
        parallelToleranceDegrees: parallelToleranceDegrees,
        minParallelLineSeparation: minParallelLineSeparation,
      );
    }

    test('accepts intersections at and beyond both through-points', () {
      final atThroughPoint = intersection(
        const Offset(0, 0),
        const Offset(1, 0),
        const Offset(1, -1),
        const Offset(1, 0),
      );
      expect(atThroughPoint?.kind, ForwardRayIntersectionKind.finite);
      expect(atThroughPoint?.point, const Offset(1, 0));

      final beyondBoth = intersection(
        const Offset(0, 0),
        const Offset(1, 1),
        const Offset(4, 0),
        const Offset(3, 1),
      );
      expect(beyondBoth?.kind, ForwardRayIntersectionKind.finite);
      expect(beyondBoth?.point, const Offset(2, 2));
    });

    test('accepts a finite forward intersection at any distance', () {
      final result = intersection(
        const Offset(0, 0),
        const Offset(1, 0),
        const Offset(100, -1),
        const Offset(100, 0),
      );
      expect(result?.kind, ForwardRayIntersectionKind.finite);
      expect(result?.point, const Offset(100, 0));
    });

    test('is invariant when the geometry is horizontally mirrored', () {
      final result = intersection(
        const Offset(0, 0),
        const Offset(-1, 1),
        const Offset(-4, 0),
        const Offset(-3, 1),
      );
      expect(result?.kind, ForwardRayIntersectionKind.finite);
      expect(result?.point, const Offset(-2, 2));
    });

    test('requires a finite intersection in quadrant 4 or 3', () {
      const rightIntersection = ForwardRayIntersection2D.finite(Offset(8, 8));
      const leftIntersection = ForwardRayIntersection2D.finite(Offset(2, 8));
      final firstStart = _landmark(const Offset(0, 0));
      final firstThrough = _landmark(const Offset(1, 1));
      final secondStart = _landmark(const Offset(0, 2));
      final secondThrough = _landmark(const Offset(1, 1));

      expect(
        geometry.isForwardRayRelationInHandQuadrant2D(
          relation: rightIntersection,
          firstStart: firstStart,
          firstThrough: firstThrough,
          secondStart: secondStart,
          secondThrough: secondThrough,
          imageSize: const Size(10, 10),
          handedness: Handedness.right,
          mirrorHorizontally: false,
        ),
        isTrue,
      );
      expect(
        geometry.isForwardRayRelationInHandQuadrant2D(
          relation: leftIntersection,
          firstStart: firstStart,
          firstThrough: firstThrough,
          secondStart: secondStart,
          secondThrough: secondThrough,
          imageSize: const Size(10, 10),
          handedness: Handedness.left,
          mirrorHorizontally: false,
        ),
        isTrue,
      );
      expect(
        geometry.isForwardRayRelationInHandQuadrant2D(
          relation: leftIntersection,
          firstStart: firstStart,
          firstThrough: firstThrough,
          secondStart: secondStart,
          secondThrough: secondThrough,
          imageSize: const Size(10, 10),
          handedness: Handedness.right,
          mirrorHorizontally: false,
        ),
        isFalse,
      );
      expect(
        geometry.isForwardRayRelationInHandQuadrant2D(
          relation: const ForwardRayIntersection2D.finite(Offset(5, 8)),
          firstStart: firstStart,
          firstThrough: firstThrough,
          secondStart: secondStart,
          secondThrough: secondThrough,
          imageSize: const Size(10, 10),
          handedness: Handedness.right,
          mirrorHorizontally: false,
        ),
        isFalse,
        reason: 'an intersection on the vertical axis is not in quadrant 4',
      );
      expect(
        geometry.isForwardRayRelationInHandQuadrant2D(
          relation: const ForwardRayIntersection2D.finite(Offset(8, 5)),
          firstStart: firstStart,
          firstThrough: firstThrough,
          secondStart: secondStart,
          secondThrough: secondThrough,
          imageSize: const Size(10, 10),
          handedness: Handedness.right,
          mirrorHorizontally: false,
        ),
        isFalse,
        reason: 'an intersection on the horizontal axis is not in quadrant 4',
      );
      expect(
        geometry.isForwardRayRelationInHandQuadrant2D(
          relation: const ForwardRayIntersection2D.finite(Offset(8, 2)),
          firstStart: firstStart,
          firstThrough: firstThrough,
          secondStart: secondStart,
          secondThrough: secondThrough,
          imageSize: const Size(10, 10),
          handedness: Handedness.right,
          mirrorHorizontally: false,
        ),
        isFalse,
      );
      expect(
        geometry.isForwardRayRelationInHandQuadrant2D(
          relation: leftIntersection,
          firstStart: firstStart,
          firstThrough: firstThrough,
          secondStart: secondStart,
          secondThrough: secondThrough,
          imageSize: const Size(10, 10),
          handedness: Handedness.right,
          mirrorHorizontally: true,
        ),
        isTrue,
      );
    });

    test('requires parallel rays to point into quadrant 4 or 3', () {
      const relation = ForwardRayIntersection2D.atInfinity();

      bool pointsToQuadrant({
        required bool pointRight,
        double verticalDelta = 1,
        required Handedness handedness,
        bool mirrorHorizontally = false,
      }) {
        final horizontalDelta = pointRight ? 1.0 : -1.0;
        return geometry.isForwardRayRelationInHandQuadrant2D(
          relation: relation,
          firstStart: _landmark(const Offset(0, 0)),
          firstThrough: _landmark(Offset(horizontalDelta, verticalDelta)),
          secondStart: _landmark(const Offset(0, 2)),
          secondThrough: _landmark(Offset(horizontalDelta, 2 + verticalDelta)),
          imageSize: const Size(10, 10),
          handedness: handedness,
          mirrorHorizontally: mirrorHorizontally,
        );
      }

      expect(
        pointsToQuadrant(pointRight: true, handedness: Handedness.right),
        isTrue,
      );
      expect(
        pointsToQuadrant(pointRight: false, handedness: Handedness.left),
        isTrue,
      );
      expect(
        pointsToQuadrant(pointRight: false, handedness: Handedness.right),
        isFalse,
      );
      expect(
        pointsToQuadrant(
          pointRight: false,
          handedness: Handedness.right,
          mirrorHorizontally: true,
        ),
        isTrue,
      );
      expect(
        pointsToQuadrant(
          pointRight: true,
          verticalDelta: 0,
          handedness: Handedness.right,
        ),
        isFalse,
      );
    });

    test('treats same-direction rays within five degrees as infinity', () {
      final exactParallel = intersection(
        const Offset(0, 0),
        const Offset(1, 0),
        const Offset(0, 1),
        const Offset(1, 1),
      );
      expect(exactParallel?.kind, ForwardRayIntersectionKind.atInfinity);
      expect(exactParallel?.point, isNull);
      expect(exactParallel?.isAtInfinity, isTrue);

      final fiveDegrees = 5 * math.pi / 180;
      final toleranceBoundary = intersection(
        const Offset(0, 0),
        const Offset(1, 0),
        const Offset(0, 1),
        Offset(math.cos(fiveDegrees), 1 + math.sin(fiveDegrees)),
      );
      expect(toleranceBoundary?.kind, ForwardRayIntersectionKind.atInfinity);
    });

    test('requires the configured gap between parallel lines', () {
      final atBoundary = intersection(
        const Offset(0, 0),
        const Offset(1, 0),
        const Offset(4, 1),
        const Offset(5, 1),
        minParallelLineSeparation: 1,
      );
      expect(atBoundary?.kind, ForwardRayIntersectionKind.atInfinity);

      expect(
        intersection(
          const Offset(0, 0),
          const Offset(1, 0),
          const Offset(4, 0.99),
          const Offset(5, 0.99),
          minParallelLineSeparation: 1,
        ),
        isNull,
      );
    });

    test('rejects intersections behind a ray outside the tolerance', () {
      final justOutsideTolerance = 5.01 * math.pi / 180;
      expect(
        intersection(
          const Offset(0, 0),
          const Offset(1, 0),
          const Offset(0, 1),
          Offset(
            math.cos(justOutsideTolerance),
            1 + math.sin(justOutsideTolerance),
          ),
        ),
        isNull,
      );

      expect(
        intersection(
          const Offset(0, 0),
          const Offset(1, 0),
          const Offset(2, 1),
          const Offset(2, 2),
        ),
        isNull,
      );
    });

    test('rejects degenerate and opposite-facing parallel rays', () {
      expect(
        intersection(
          const Offset(0, 0),
          const Offset(0, 0),
          const Offset(1, 0),
          const Offset(1, 1),
        ),
        isNull,
      );
      expect(
        intersection(
          const Offset(0, 0),
          const Offset(1, 0),
          const Offset(2, 0),
          const Offset(1, 0),
        ),
        isNull,
      );
    });

    test('rejects non-finite coordinates and thresholds', () {
      expect(
        intersection(
          const Offset(double.nan, 0),
          const Offset(1, 0),
          const Offset(1, -1),
          const Offset(1, 0),
        ),
        isNull,
      );
      expect(
        intersection(
          const Offset(0, 0),
          const Offset(1, 0),
          const Offset(1, -1),
          const Offset(1, 0),
          parallelToleranceDegrees: double.infinity,
        ),
        isNull,
      );
      expect(
        intersection(
          const Offset(0, 0),
          const Offset(1, 0),
          const Offset(1, -1),
          const Offset(1, 0),
          parallelToleranceDegrees: 90,
        ),
        isNull,
      );
    });
  });

  group('HandGeometryService downwardExtendedFingerChainCount', () {
    const geometry = HandGeometryService();

    test('returns zero for non-finite image sizes', () {
      expect(
        geometry.downwardExtendedFingerChainCount(
          hand: _handWithDownwardFingerChains(),
          imageSize: const Size(double.nan, 400),
          mirrorHorizontally: false,
        ),
        0,
      );

      expect(
        geometry.downwardExtendedFingerChainCount(
          hand: _handWithDownwardFingerChains(),
          imageSize: const Size(400, double.infinity),
          mirrorHorizontally: false,
        ),
        0,
      );
    });
  });
}

HandLandmark _landmark(Offset point) {
  return HandLandmark(
    type: HandLandmarkType.indexFingerTip,
    x: point.dx,
    y: point.dy,
    z: 0,
    visibility: 1,
  );
}

Hand _handWithLandmark({
  double x = 120,
  double y = 180,
  double z = 0,
  double visibility = 1,
  double score = 1,
  BoundingBox? boundingBox,
}) {
  return Hand(
    boundingBox: boundingBox ?? BoundingBox.ltrb(0, 0, 400, 400),
    score: score,
    landmarks: [
      HandLandmark(
        type: HandLandmarkType.indexFingerTip,
        x: x,
        y: y,
        z: z,
        visibility: visibility,
      ),
    ],
    imageWidth: 400,
    imageHeight: 400,
    handedness: Handedness.right,
  );
}

Hand _handWithoutLandmarks({double score = 1}) {
  return Hand(
    boundingBox: BoundingBox.ltrb(0, 0, 400, 400),
    score: score,
    landmarks: const [],
    imageWidth: 400,
    imageHeight: 400,
    handedness: Handedness.right,
  );
}

Hand _handWithDownwardFingerChains() {
  final landmarks = <HandLandmark>[];
  final chains = [
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
  ];
  final bases = [
    const Offset(170, 120),
    const Offset(200, 120),
    const Offset(230, 120),
  ];

  for (var fingerIndex = 0; fingerIndex < chains.length; fingerIndex++) {
    final base = bases[fingerIndex];
    for (
      var pointIndex = 0;
      pointIndex < chains[fingerIndex].length;
      pointIndex++
    ) {
      landmarks.add(
        HandLandmark(
          type: chains[fingerIndex][pointIndex],
          x: base.dx,
          y: base.dy + pointIndex * 35,
          z: 0,
          visibility: 1,
        ),
      );
    }
  }

  return Hand(
    boundingBox: BoundingBox.ltrb(0, 0, 400, 400),
    score: 1,
    landmarks: landmarks,
    imageWidth: 400,
    imageHeight: 400,
    handedness: Handedness.right,
  );
}
