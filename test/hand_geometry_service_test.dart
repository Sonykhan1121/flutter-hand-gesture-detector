import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gesture_detector/hand_gesture_features/domain/constants/hand_gesture_thresholds.dart';
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

  group('HandGeometryService palm-side orientation', () {
    const geometry = HandGeometryService();

    bool isPalm(Hand hand, {bool mirrorHorizontally = false}) =>
        geometry.isPalmSideFacingCamera(
          hand: hand,
          mirrorHorizontally: mirrorHorizontally,
          minNormalizedCross: 0.10,
          minLandmarkVisibility: 0.5,
        );

    test('accepts right and left palms with chirality correction', () {
      expect(isPalm(_palmOrientationHand()), isTrue);
      expect(
        isPalm(
          _palmOrientationHand(mirrorPose: true, handedness: Handedness.left),
        ),
        isTrue,
      );
    });

    test('accepts a mirrored right palm only with coordinate correction', () {
      final mirroredPalm = _palmOrientationHand(mirrorPose: true);

      expect(isPalm(mirroredPalm), isFalse);
      expect(isPalm(mirroredPalm, mirrorHorizontally: true), isTrue);
    });

    test('fails closed for unknown handedness and unreliable anchors', () {
      expect(isPalm(_palmOrientationHand(handedness: null)), isFalse);
      expect(
        isPalm(
          _palmOrientationHand(missingTypes: const {HandLandmarkType.wrist}),
        ),
        isFalse,
      );
      expect(
        isPalm(
          _palmOrientationHand(
            lowVisibilityTypes: const {HandLandmarkType.pinkyMCP},
          ),
        ),
        isFalse,
      );
    });
  });

  group('HandGeometryService palm landmark circle', () {
    const geometry = HandGeometryService();

    PalmLandmarkCircleEvaluation? evaluate(
      Hand hand, {
      Size imageSize = const Size(200, 300),
    }) => geometry.evaluatePalmLandmarkCircle2D(
      hand: hand,
      imageSize: imageSize,
      requiredTypes: HandGestureThresholds.directionCompactPalmCircleTypes,
      radiusPalmWidthRatio:
          HandGestureThresholds.directionCompactPalmCircleRadiusPalmWidthRatio,
      minimumRadiusImageShortSideRatio:
          HandGestureThresholds
              .directionCompactPalmCircleMinImageShortSideRatio,
    );

    test('accepts point 5 and points 9-20 inside the palm-scaled circle', () {
      final result = evaluate(_compactCircleHand());

      expect(result, isNotNull);
      expect(result!.allRequiredInside, isTrue);
      expect(result.center, const Offset(145, 208));
      expect(result.palmScaledRadius, 81);
      expect(result.minimumRadius, 30);
      expect(result.radius, 81);
      expect(result.minimumRadiusApplied, isFalse);
      expect(result.insideCount, result.requiredCount);
      expect(result.requiredCount, 13);
    });

    test('clamps a small hand to 15% of the image shorter side', () {
      final result = evaluate(
        _compactCircleHand(),
        imageSize: const Size(1000, 800),
      );

      expect(result, isNotNull);
      expect(result!.palmScaledRadius, 81);
      expect(result.minimumRadius, 120);
      expect(result.radius, 120);
      expect(result.minimumRadiusApplied, isTrue);
    });

    test('uses the same minimum in portrait and landscape frames', () {
      final portrait = evaluate(
        _compactCircleHand(),
        imageSize: const Size(800, 1000),
      );
      final landscape = evaluate(
        _compactCircleHand(),
        imageSize: const Size(1000, 800),
      );

      expect(portrait!.minimumRadius, 120);
      expect(landscape!.minimumRadius, 120);
      expect(portrait.radius, landscape.radius);
    });

    test('keeps the shared radius at the exact equality boundary', () {
      final result = evaluate(
        _compactCircleHand(),
        imageSize: const Size(540, 800),
      );

      expect(result, isNotNull);
      expect(result!.palmScaledRadius, 81);
      expect(result.minimumRadius, 81);
      expect(result.radius, 81);
      expect(result.minimumRadiusApplied, isFalse);
    });

    test('accepts the final-radius boundary and rejects beyond it', () {
      final onBoundary = evaluate(
        _compactCircleHand(
          overrides: const {HandLandmarkType.pinkyTip: Offset(265, 208)},
        ),
        imageSize: const Size(1000, 800),
      );
      final beyondBoundary = evaluate(
        _compactCircleHand(
          overrides: const {HandLandmarkType.pinkyTip: Offset(265.01, 208)},
        ),
        imageSize: const Size(1000, 800),
      );

      expect(onBoundary!.radius, 120);
      expect(onBoundary.insideByType[HandLandmarkType.pinkyTip], isTrue);
      expect(beyondBoundary!.insideByType[HandLandmarkType.pinkyTip], isFalse);
    });

    test('reports a visible point outside the palm-scaled circle', () {
      final result = evaluate(
        _compactCircleHand(
          overrides: const {HandLandmarkType.pinkyTip: Offset(190, 70)},
        ),
      );

      expect(result, isNotNull);
      expect(result!.allRequiredInside, isFalse);
      expect(result.insideByType[HandLandmarkType.pinkyTip], isFalse);
    });

    test('fails closed when an MCP circle anchor is missing', () {
      expect(
        evaluate(
          _compactCircleHand(
            missingTypes: const {HandLandmarkType.ringFingerMCP},
          ),
        ),
        isNull,
      );
    });

    test('fails closed when wrist point 0 is missing', () {
      expect(
        evaluate(
          _compactCircleHand(missingTypes: const {HandLandmarkType.wrist}),
        ),
        isNull,
      );
    });

    test('fails closed for invalid image dimensions', () {
      expect(
        evaluate(_compactCircleHand(), imageSize: const Size(0, 400)),
        isNull,
      );
      expect(
        evaluate(_compactCircleHand(), imageSize: const Size(double.nan, 400)),
        isNull,
      );
    });
  });

  group('HandGeometryService Punch circle', () {
    const geometry = HandGeometryService();

    test('uses the 5/13 distance when it exceeds 30% hand size', () {
      final result = geometry.evaluatePunchMiddleFingerCircle(
        _compactCircleHand(),
      );

      expect(result, isNotNull);
      expect(result!.center, const Offset(130, 185));
      expect(result.handSizeRadius, 45);
      expect(result.minimumRadius, 60);
      expect(result.radius, 60);
      expect(result.minimumRadiusApplied, isTrue);
      expect(
        HandGestureThresholds.punchCircleRadiusHandSizeRatio,
        0.30,
      );
    });

    test('uses point 10 alone when point 9 is unavailable', () {
      final result = geometry.evaluatePunchMiddleFingerCircle(
        _compactCircleHand(
          missingTypes: const {HandLandmarkType.middleFingerMCP},
        ),
      );

      expect(result, isNotNull);
      expect(result!.center, const Offset(130, 170));
      expect(result.radius, 60);
    });

    test('uses the normal 30% radius when a 5/13 anchor is unavailable', () {
      final result = geometry.evaluatePunchMiddleFingerCircle(
        _compactCircleHand(
          missingTypes: const {HandLandmarkType.indexFingerMCP},
        ),
      );

      expect(result, isNotNull);
      expect(result!.handSizeRadius, 45);
      expect(result.minimumRadius, 0);
      expect(result.radius, 45);
      expect(result.minimumRadiusApplied, isFalse);
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

  group('HandGeometryService direction finger compression', () {
    const geometry = HandGeometryService();

    HandLandmark point(double x, double y, {double z = 0}) {
      return HandLandmark(
        type: HandLandmarkType.middleFingerMCP,
        x: x,
        y: y,
        z: z,
        visibility: 1,
      );
    }

    test('is near one for a straight chain and small for a curled chain', () {
      expect(
        geometry.fingerCompressionRatio3D(
          mcp: point(0, 0),
          pip: point(0, -10),
          dip: point(0, -20),
          tip: point(0, -30),
        ),
        closeTo(1, 1e-9),
      );

      final compression = geometry.fingerCompressionRatio3D(
        mcp: point(0, 0),
        pip: point(0, -30),
        dip: point(0, -60),
        tip: point(0, -5),
      );
      expect(compression, closeTo(5 / 115, 1e-9));
      expect(
        geometry.isFingerFoldedByCompression3D(
          mcp: point(0, 0),
          pip: point(0, -30),
          dip: point(0, -60),
          tip: point(0, -5),
          palmWidth: 50,
        ),
        isTrue,
      );
    });

    test('uses squared finger reach as a palm-relative area ratio', () {
      expect(
        geometry.fingerReachAreaRatio3D(
          mcp: point(0, 0),
          tip: point(0, -35),
          palmWidth: 50,
        ),
        closeTo(0.49, 1e-9),
      );
      expect(
        geometry.fingerReachAreaRatio3D(
          mcp: point(0, 0),
          tip: point(0, -45),
          palmWidth: 50,
        ),
        closeTo(0.81, 1e-9),
      );
    });

    test('uses squared top spread and MCP reach for the cluster area', () {
      final mcp = point(0, 0);
      final pip = point(0, -20);
      final dip = point(0, -30);
      final tip = point(0, -35);

      expect(
        geometry.fingerTopClusterAreaRatio3D(
          pip: pip,
          dip: dip,
          tip: tip,
          palmWidth: 50,
        ),
        closeTo(0.09, 1e-9),
      );
      expect(
        geometry.fingerTopMaxMcpAreaRatio3D(
          mcp: mcp,
          pip: pip,
          dip: dip,
          tip: tip,
          palmWidth: 50,
        ),
        closeTo(0.49, 1e-9),
      );
      expect(
        geometry.isFingerTopClusterFolded3D(
          mcp: mcp,
          pip: pip,
          dip: dip,
          tip: tip,
          palmWidth: 50,
        ),
        isTrue,
      );
    });

    test(
      'accepts the 80 percent compression boundary inside the easier reach',
      () {
        expect(
          geometry.isFingerFoldedByCompression3D(
            mcp: point(0, 0),
            pip: point(0, 5),
            dip: point(0, 0),
            tip: point(40, 0),
            palmWidth: 50,
          ),
          isTrue,
        );
      },
    );

    test('accepts the easier 85 percent MCP-to-tip distance boundary', () {
      expect(
        geometry.isFingerFoldedByCompression3D(
          mcp: point(0, 0),
          pip: point(0, 30),
          dip: point(0, 60),
          tip: point(42.5, 0),
          palmWidth: 50,
        ),
        isTrue,
      );
    });

    test('accepts the easier 16 percent top and 85 percent near distance', () {
      expect(
        geometry.isFingerTopClusterFolded3D(
          mcp: point(0, 0),
          pip: point(22.5, 0),
          dip: point(32.5, 0),
          tip: point(42.5, 0),
          palmWidth: 50,
        ),
        isTrue,
      );
    });

    test(
      'requires both 81 percent reach area and 85 percent compression to be open',
      () {
        expect(
          geometry.isFingerClearlyOpenByArea3D(
            mcp: point(0, 0),
            pip: point(0, -15),
            dip: point(0, -30),
            tip: point(0, -45),
            palmWidth: 50,
          ),
          isTrue,
        );
        expect(
          geometry.isFingerClearlyOpenByArea3D(
            mcp: point(0, 0),
            pip: point(0, -15),
            dip: point(0, -30),
            tip: point(0, -44.5),
            palmWidth: 50,
          ),
          isFalse,
        );
      },
    );

    test('gives the same folded result from opposite depth orientations', () {
      for (final depthSign in const [-1.0, 1.0]) {
        expect(
          geometry.isFingerFoldedByCompression3D(
            mcp: point(0, 0),
            pip: point(0, -30, z: 0.10 * depthSign),
            dip: point(0, -60, z: 0.20 * depthSign),
            tip: point(0, -5, z: 0.02 * depthSign),
            palmWidth: 50,
          ),
          isTrue,
        );
      }
    });

    test('requires the folded fingertip to remain near its MCP', () {
      final mcp = point(0, 0);
      final pip = point(0, -30);
      final dip = point(0, -60);
      final tip = point(35, -35);

      expect(
        geometry.fingerCompressionRatio3D(
          mcp: mcp,
          pip: pip,
          dip: dip,
          tip: tip,
        ),
        lessThan(0.70),
      );
      expect(
        geometry.isFingerFoldedByCompression3D(
          mcp: mcp,
          pip: pip,
          dip: dip,
          tip: tip,
          palmWidth: 50,
        ),
        isFalse,
      );
    });

    test('rejects a degenerate chain', () {
      final samePoint = point(0, 0);
      expect(
        geometry.fingerCompressionRatio3D(
          mcp: samePoint,
          pip: samePoint,
          dip: samePoint,
          tip: samePoint,
        ),
        isNull,
      );
      expect(
        geometry.isFingerFoldedByCompression3D(
          mcp: samePoint,
          pip: samePoint,
          dip: samePoint,
          tip: samePoint,
          palmWidth: 50,
        ),
        isFalse,
      );
    });
  });

  group('HandGeometryService descending finger-chain order', () {
    const geometry = HandGeometryService();

    HandLandmark point(double y) => HandLandmark(
      type: HandLandmarkType.indexFingerMCP,
      x: 20,
      y: y,
      z: 0,
      visibility: 1,
    );

    test('accepts all three adjacent pairs at the exact minimum gap', () {
      final result = geometry.evaluateDescendingFingerChain(
        chain: [point(0), point(4), point(8), point(12)],
        handSize: 100,
        minAdjacentGapRatio: 0.04,
      );

      expect(result, isNotNull);
      expect(result!.adjacentVerticalGapRatios, [0.04, 0.04, 0.04]);
      expect(result.adjacentPairMatches, [isTrue, isTrue, isTrue]);
      expect(result.matches, isTrue);
    });

    test('rejects a too-close pair and a locally reversed pair', () {
      final tooClose = geometry.evaluateDescendingFingerChain(
        chain: [point(0), point(4), point(7.9), point(12)],
        handSize: 100,
        minAdjacentGapRatio: 0.04,
      );
      final reversed = geometry.evaluateDescendingFingerChain(
        chain: [point(0), point(4), point(3), point(12)],
        handSize: 100,
        minAdjacentGapRatio: 0.04,
      );

      expect(tooClose!.adjacentPairMatches, [isTrue, isFalse, isTrue]);
      expect(tooClose.matches, isFalse);
      expect(reversed!.adjacentPairMatches, [isTrue, isFalse, isTrue]);
      expect(reversed.matches, isFalse);
    });

    test('rejects incomplete chains and invalid scale inputs', () {
      expect(
        geometry.evaluateDescendingFingerChain(
          chain: [point(0), point(4), point(8)],
          handSize: 100,
          minAdjacentGapRatio: 0.04,
        ),
        isNull,
      );
      expect(
        geometry.evaluateDescendingFingerChain(
          chain: [point(0), point(4), point(8), point(12)],
          handSize: 0,
          minAdjacentGapRatio: 0.04,
        ),
        isNull,
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

Hand _palmOrientationHand({
  bool mirrorPose = false,
  Handedness? handedness = Handedness.right,
  Set<HandLandmarkType> missingTypes = const {},
  Set<HandLandmarkType> lowVisibilityTypes = const {},
}) {
  const mirrorAxisX = 110.0;
  final landmarks = <HandLandmark>[];

  void add(HandLandmarkType type, Offset point) {
    if (missingTypes.contains(type)) return;
    final x = mirrorPose ? 2 * mirrorAxisX - point.dx : point.dx;
    landmarks.add(
      HandLandmark(
        type: type,
        x: x,
        y: point.dy,
        z: 0,
        visibility: lowVisibilityTypes.contains(type) ? 0.2 : 1,
      ),
    );
  }

  add(HandLandmarkType.wrist, const Offset(100, 180));
  add(HandLandmarkType.indexFingerMCP, const Offset(80, 120));
  add(HandLandmarkType.pinkyMCP, const Offset(140, 120));

  return Hand(
    boundingBox: BoundingBox.ltrb(50, 80, 170, 200),
    score: 1,
    landmarks: landmarks,
    imageWidth: 400,
    imageHeight: 400,
    handedness: handedness,
  );
}

Hand _compactCircleHand({
  Map<HandLandmarkType, Offset> overrides = const {},
  Set<HandLandmarkType> missingTypes = const {},
}) {
  const positions = <HandLandmarkType, Offset>{
    HandLandmarkType.wrist: Offset(145, 240),
    HandLandmarkType.indexFingerMCP: Offset(100, 200),
    HandLandmarkType.middleFingerMCP: Offset(130, 200),
    HandLandmarkType.middleFingerPIP: Offset(130, 170),
    HandLandmarkType.middleFingerDIP: Offset(140, 180),
    HandLandmarkType.middleFingerTip: Offset(135, 195),
    HandLandmarkType.ringFingerMCP: Offset(160, 200),
    HandLandmarkType.ringFingerPIP: Offset(160, 170),
    HandLandmarkType.ringFingerDIP: Offset(170, 180),
    HandLandmarkType.ringFingerTip: Offset(165, 195),
    HandLandmarkType.pinkyMCP: Offset(190, 200),
    HandLandmarkType.pinkyPIP: Offset(185, 170),
    HandLandmarkType.pinkyDIP: Offset(190, 180),
    HandLandmarkType.pinkyTip: Offset(185, 195),
  };

  return Hand(
    boundingBox: BoundingBox.ltrb(70, 100, 220, 240),
    score: 1,
    landmarks: [
      for (final entry in positions.entries)
        if (!missingTypes.contains(entry.key))
          HandLandmark(
            type: entry.key,
            x: (overrides[entry.key] ?? entry.value).dx,
            y: (overrides[entry.key] ?? entry.value).dy,
            z: 0,
            visibility: 1,
          ),
    ],
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
