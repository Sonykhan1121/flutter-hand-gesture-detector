import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gesture_detector/hand_gesture_features/domain/constants/hand_gesture_thresholds.dart';
import 'package:gesture_detector/hand_gesture_features/domain/enums/zoom_direction.dart';
import 'package:gesture_detector/hand_gesture_features/domain/services/zoom_gesture_detector.dart';
import 'package:hand_detection/hand_detection.dart';

const _imageSize = Size(400, 400);

void main() {
  group('ZoomGestureDetector static holds', () {
    late DateTime now;
    late ZoomGestureDetector detector;

    setUp(() {
      now = DateTime(2026, 7, 18, 11);
      detector = ZoomGestureDetector(now: () => now);
    });

    test('angle-based pose zooms in at exactly one second', () {
      final hand = _zoomHand(tipDistance: 80);

      expect(_detect(detector, hand), ZoomDirection.none);
      expect(detector.pendingDirection, ZoomDirection.zoomIn);
      expect(detector.isGestureActive, isTrue);
      expect(detector.hasZoomInDebugPose, isTrue);

      now = now.add(const Duration(milliseconds: 999));
      expect(_detect(detector, hand), ZoomDirection.none);

      now = now.add(const Duration(milliseconds: 1));
      expect(_detect(detector, hand), ZoomDirection.zoomIn);
    });

    for (final angle in const [169.0, 170.0, 180.0]) {
      test('zoom in ignores the 6-7-8 angle at $angle degrees', () {
        final hand = _zoomHandWithDistalIndexAngle(angle);

        expect(_detect(detector, hand), ZoomDirection.none);
        expect(detector.pendingDirection, ZoomDirection.zoomIn);

        now = now.add(const Duration(seconds: 1));
        expect(_detect(detector, hand), ZoomDirection.zoomIn);
      });
    }

    test('closed pinch at the exact 2% gap zooms out after one second', () {
      final hand = _zoomOutHand();

      expect(_detect(detector, hand), ZoomDirection.none);
      expect(detector.pendingDirection, ZoomDirection.zoomOut);
      expect(detector.hasZoomInDebugPose, isFalse);

      now = now.add(const Duration(seconds: 1));
      expect(_detect(detector, hand), ZoomDirection.zoomOut);
    });

    test('touching tips can zoom out when the index segment is above', () {
      final hand = _touchingZoomOutHand();

      expect(_detect(detector, hand), ZoomDirection.none);
      expect(detector.pendingDirection, ZoomDirection.zoomOut);

      now = now.add(const Duration(seconds: 1));
      expect(_detect(detector, hand), ZoomDirection.zoomOut);
    });

    test('zoom out does not require the index PIP landmark', () {
      final hand = _zoomOutHand(
        missingTypes: const {HandLandmarkType.indexFingerPIP},
      );

      expect(_detect(detector, hand), ZoomDirection.none);
      expect(detector.pendingDirection, ZoomDirection.zoomOut);

      now = now.add(const Duration(seconds: 1));
      expect(_detect(detector, hand), ZoomDirection.zoomOut);
    });

    test('screen-space touching still zooms out with noisy depth', () {
      final hand = _touchingZoomOutHand(
        landmarkZOverrides: const {
          HandLandmarkType.thumbTip: 40,
          HandLandmarkType.indexFingerTip: -40,
        },
      );

      expect(_detect(detector, hand), ZoomDirection.none);
      expect(detector.pendingDirection, ZoomDirection.zoomOut);

      now = now.add(const Duration(seconds: 1));
      expect(_detect(detector, hand), ZoomDirection.zoomOut);
    });

    test('an opening below the fingertip separation stays neutral', () {
      final hand = _angleHand(30);

      expect(_detect(detector, hand), ZoomDirection.none);
      expect(detector.pendingDirection, ZoomDirection.none);
      expect(detector.isGestureActive, isFalse);
      expect(detector.hasZoomInDebugPose, isTrue);
    });

    test('continues returning zoom in while the pose stays held', () {
      final hand = _zoomHand(tipDistance: 80);

      expect(_detect(detector, hand), ZoomDirection.none);
      now = now.add(const Duration(seconds: 1));
      expect(_detect(detector, hand), ZoomDirection.zoomIn);
      now = now.add(const Duration(seconds: 1));
      expect(_detect(detector, hand), ZoomDirection.zoomIn);
      expect(
        HandGestureThresholds.gestureZoomRepeatInterval,
        const Duration(seconds: 1),
      );
    });

    for (final rotation in const [90.0, 180.0]) {
      test('rejects $rotation degree roll when index is no longer above', () {
        final hand = _zoomHand(tipDistance: 80, rotationDegrees: rotation);

        expect(_detect(detector, hand), ZoomDirection.none);
        expect(detector.pendingDirection, ZoomDirection.none);
      });
    }

    test('mirrored palm zooms in with palm chirality correction', () {
      final hand = _zoomHand(tipDistance: 80, mirrorPose: true);

      expect(
        _detect(detector, hand, mirrorHorizontally: true),
        ZoomDirection.none,
      );
      expect(detector.pendingDirection, ZoomDirection.zoomIn);
      now = now.add(const Duration(seconds: 1));
      expect(
        _detect(detector, hand, mirrorHorizontally: true),
        ZoomDirection.zoomIn,
      );
    });

    test('mirrored palm zooms out with palm chirality correction', () {
      final hand = _zoomOutHand(mirrorPose: true);

      expect(
        _detect(detector, hand, mirrorHorizontally: true),
        ZoomDirection.none,
      );
      expect(detector.pendingDirection, ZoomDirection.zoomOut);
      now = now.add(const Duration(seconds: 1));
      expect(
        _detect(detector, hand, mirrorHorizontally: true),
        ZoomDirection.zoomOut,
      );
    });

    test('back of hand cannot start zoom in', () {
      final hand = _zoomHand(tipDistance: 80, mirrorPose: true);

      expect(_detect(detector, hand), ZoomDirection.none);
      expect(detector.pendingDirection, ZoomDirection.none);
      expect(detector.isGestureActive, isFalse);
    });

    test('left palm can start zoom in with matching handedness', () {
      final hand = _zoomHand(
        tipDistance: 80,
        mirrorPose: true,
        handedness: Handedness.left,
      );

      expect(_detect(detector, hand), ZoomDirection.none);
      expect(detector.pendingDirection, ZoomDirection.zoomIn);
      now = now.add(const Duration(seconds: 1));
      expect(_detect(detector, hand), ZoomDirection.zoomIn);
    });

    test('left palm can start zoom out with matching handedness', () {
      final hand = _zoomOutHand(mirrorPose: true, handedness: Handedness.left);

      expect(_detect(detector, hand), ZoomDirection.none);
      expect(detector.pendingDirection, ZoomDirection.zoomOut);
      now = now.add(const Duration(seconds: 1));
      expect(_detect(detector, hand), ZoomDirection.zoomOut);
    });

    test('unknown handedness cannot prove palm-side zoom in', () {
      final hand = _zoomHand(tipDistance: 80, handedness: null);

      expect(_detect(detector, hand), ZoomDirection.none);
      expect(detector.pendingDirection, ZoomDirection.none);
      expect(detector.isGestureActive, isFalse);
    });

    test('back of hand cannot start zoom out', () {
      final hand = _zoomOutHand(mirrorPose: true);

      expect(_detect(detector, hand), ZoomDirection.none);
      expect(detector.pendingDirection, ZoomDirection.none);
      expect(detector.isGestureActive, isFalse);
      now = now.add(const Duration(seconds: 1));
      expect(_detect(detector, hand), ZoomDirection.none);
      expect(detector.reservesZoomInOpeningTransition, isFalse);
    });

    test('unknown handedness cannot prove palm-side zoom out', () {
      final hand = _zoomOutHand(handedness: null);

      expect(_detect(detector, hand), ZoomDirection.none);
      expect(detector.pendingDirection, ZoomDirection.none);
      expect(detector.isGestureActive, isFalse);
    });

    test('zoom out requires visible wrist, index MCP, and pinky MCP', () {
      for (final type in const {
        HandLandmarkType.wrist,
        HandLandmarkType.indexFingerMCP,
        HandLandmarkType.pinkyMCP,
      }) {
        for (final hand in [
          _zoomOutHand(missingTypes: {type}),
          _zoomOutHand(lowVisibilityTypes: {type}),
        ]) {
          detector.clearState();
          expect(_detect(detector, hand), ZoomDirection.none);
          expect(detector.pendingDirection, ZoomDirection.none);
          expect(detector.isGestureActive, isFalse);
        }
      }
    });

    test('jumping from zoom out to an open pose starts a fresh hold', () {
      expect(_detect(detector, _zoomOutHand()), ZoomDirection.none);
      now = now.add(const Duration(milliseconds: 800));
      expect(_detect(detector, _zoomHand(tipDistance: 80)), ZoomDirection.none);
      expect(detector.pendingDirection, ZoomDirection.zoomIn);

      now = now.add(const Duration(milliseconds: 999));
      expect(_detect(detector, _zoomHand(tipDistance: 80)), ZoomDirection.none);
      now = now.add(const Duration(milliseconds: 1));
      expect(
        _detect(detector, _zoomHand(tipDistance: 80)),
        ZoomDirection.zoomIn,
      );
    });

    test('transition waits for a forward intersection before zooming in', () {
      final closed = _rightAngleHandWithTipDistance(
        HandGestureThresholds.zoomClosedMaxDistanceRatio * 200,
      );
      final released = _rightAngleHandWithTipDistance(40);

      expect(_detect(detector, closed), ZoomDirection.none);
      now = now.add(const Duration(seconds: 1));
      expect(_detect(detector, closed), ZoomDirection.zoomOut);
      expect(detector.reservesZoomInOpeningTransition, isTrue);

      expect(_detect(detector, released), ZoomDirection.none);
      expect(detector.pendingDirection, ZoomDirection.zoomIn);
      expect(detector.isOpeningZoomInCandidate, isTrue);

      expect(_detect(detector, _legacyAngleHand(90)), ZoomDirection.none);
      expect(detector.isOpeningZoomInCandidate, isTrue);

      for (final angle in const [45.0, 60.0, 75.0, 90.0, 110.0]) {
        expect(
          _detect(detector, _angleHand(angle)),
          ZoomDirection.zoomIn,
          reason: '$angle degrees must remain active Zoom In',
        );
      }
    });

    test('transition completes when the rays meet at infinity', () {
      final closed = _rightAngleHandWithTipDistance(
        HandGestureThresholds.zoomClosedMaxDistanceRatio * 200,
      );

      expect(_detect(detector, closed), ZoomDirection.none);
      now = now.add(const Duration(seconds: 1));
      expect(_detect(detector, closed), ZoomDirection.zoomOut);
      expect(_detect(detector, _angleHand(30)), ZoomDirection.none);
      expect(detector.isOpeningZoomInCandidate, isTrue);
      expect(_detect(detector, _parallelZoomInHand()), ZoomDirection.zoomIn);
    });

    test('transition cannot complete for too-close parallel lines', () {
      final closed = _rightAngleHandWithTipDistance(
        HandGestureThresholds.zoomClosedMaxDistanceRatio * 200,
      );

      expect(_detect(detector, closed), ZoomDirection.none);
      now = now.add(const Duration(seconds: 1));
      expect(_detect(detector, closed), ZoomDirection.zoomOut);
      expect(_detect(detector, _angleHand(30)), ZoomDirection.none);
      expect(detector.isOpeningZoomInCandidate, isTrue);

      expect(
        _detect(detector, _closeParallelZoomInHand(lineSeparation: 19.9)),
        ZoomDirection.none,
      );
      expect(detector.isOpeningZoomInCandidate, isTrue);
    });

    test('transition completes for a distant forward intersection', () {
      final closed = _rightAngleHandWithTipDistance(
        HandGestureThresholds.zoomClosedMaxDistanceRatio * 200,
      );

      expect(_detect(detector, closed), ZoomDirection.none);
      now = now.add(const Duration(seconds: 1));
      expect(_detect(detector, closed), ZoomDirection.zoomOut);
      expect(_detect(detector, _angleHand(30)), ZoomDirection.none);
      expect(detector.isOpeningZoomInCandidate, isTrue);
      expect(
        _detect(detector, _angleHand(6, tipDistance: 80)),
        ZoomDirection.zoomIn,
      );
    });

    test('released pinch cannot start candidate before zoom out completes', () {
      final closed = _rightAngleHandWithTipDistance(
        HandGestureThresholds.zoomClosedMaxDistanceRatio * 200,
      );

      expect(_detect(detector, closed), ZoomDirection.none);
      expect(
        _detect(detector, _rightAngleHandWithTipDistance(40)),
        ZoomDirection.none,
      );
      expect(detector.pendingDirection, ZoomDirection.none);
      expect(detector.reservesZoomInOpeningTransition, isFalse);
    });
  });

  group('ZoomGestureDetector simplified zoom-in geometry', () {
    late DateTime now;
    late ZoomGestureDetector detector;

    setUp(() {
      now = DateTime(2026, 7, 18, 11);
      detector = ZoomGestureDetector(now: () => now);
    });

    for (final angle in const [45.0, 60.0, 75.0, 90.0, 91.0, 110.0, 160.0]) {
      test('accepts a $angle degree pose with a forward intersection', () {
        final hand = _angleHand(angle);

        expect(_detect(detector, hand), ZoomDirection.none);
        expect(detector.pendingDirection, ZoomDirection.zoomIn);
        now = now.add(const Duration(seconds: 1));
        expect(_detect(detector, hand), ZoomDirection.zoomIn);
      });
    }

    for (final angle in const [20.0, 44.0]) {
      test('accepts $angle degrees below the former angle boundary', () {
        final hand = _angleHand(angle, tipDistance: 80);

        expect(_detect(detector, hand), ZoomDirection.none);
        expect(detector.pendingDirection, ZoomDirection.zoomIn);
        now = now.add(const Duration(seconds: 1));
        expect(_detect(detector, hand), ZoomDirection.zoomIn);
      });
    }

    for (final angle in const [0.0, 5.0]) {
      test('accepts same-direction rays at $angle degrees as infinity', () {
        final hand = _parallelZoomInHand(angleDegrees: angle);

        expect(_detect(detector, hand), ZoomDirection.none);
        expect(detector.pendingDirection, ZoomDirection.zoomIn);
        now = now.add(const Duration(seconds: 1));
        expect(_detect(detector, hand), ZoomDirection.zoomIn);
      });
    }

    test('rejects parallel rays whose lines are too close', () {
      final hand = _closeParallelZoomInHand(lineSeparation: 19.9);

      expect(_detect(detector, hand), ZoomDirection.none);
      expect(detector.pendingDirection, ZoomDirection.none);
      expect(detector.hasZoomInDebugPose, isTrue);
    });

    test('accepts the exact parallel line-separation boundary', () {
      final hand = _closeParallelZoomInHand(lineSeparation: 20);

      expect(_detect(detector, hand), ZoomDirection.none);
      expect(detector.pendingDirection, ZoomDirection.zoomIn);
      now = now.add(const Duration(seconds: 1));
      expect(_detect(detector, hand), ZoomDirection.zoomIn);
    });

    test('accepts a forward intersection beyond two hand sizes', () {
      final hand = _angleHand(6, tipDistance: 80);

      expect(_detect(detector, hand), ZoomDirection.none);
      expect(detector.pendingDirection, ZoomDirection.zoomIn);
      now = now.add(const Duration(seconds: 1));
      expect(_detect(detector, hand), ZoomDirection.zoomIn);
    });

    test('rejects a right-hand intersection outside quadrant 4', () {
      final hand = _angleHand(60, mirrorRayGeometry: true);

      expect(_detect(detector, hand), ZoomDirection.none);
      expect(detector.pendingDirection, ZoomDirection.none);
      expect(detector.hasZoomInDebugPose, isTrue);
    });

    test('rejects a right-hand intersection in quadrant 1', () {
      final hand = _angleHand(60, rayOffset: const Offset(0, -200));

      expect(_detect(detector, hand), ZoomDirection.none);
      expect(detector.pendingDirection, ZoomDirection.none);
      expect(detector.hasZoomInDebugPose, isTrue);
    });

    test('rejects right-hand parallel rays pointing outside quadrant 4', () {
      final hand = _parallelZoomInHand(pointLeft: true);

      expect(_detect(detector, hand), ZoomDirection.none);
      expect(detector.pendingDirection, ZoomDirection.none);
      expect(detector.hasZoomInDebugPose, isTrue);
    });

    test('rejects opposite-facing parallel rays', () {
      final hand = _parallelZoomInHand(reverseIndexRay: true);

      expect(_detect(detector, hand), ZoomDirection.none);
      expect(detector.pendingDirection, ZoomDirection.none);
    });

    test('rejects an otherwise valid angle whose intersection is behind', () {
      final hand = _legacyAngleHand(90);

      expect(_detect(detector, hand), ZoomDirection.none);
      expect(detector.pendingDirection, ZoomDirection.none);
    });

    test('overlapping tips do not bypass reversed vertical ordering', () {
      final hand = _zoomHand(
        tipDistance: 80,
        landmarkOverrides: const {
          HandLandmarkType.thumbIP: Offset(90, 90),
          HandLandmarkType.thumbTip: Offset(150, 90),
          HandLandmarkType.indexFingerDIP: Offset(150, 150),
          HandLandmarkType.indexFingerTip: Offset(150, 90),
        },
      );

      expect(_detect(detector, hand), ZoomDirection.none);
      expect(detector.pendingDirection, ZoomDirection.none);
    });

    test('a close 45 degree pose is zoom out rather than zoom in', () {
      final hand = _legacyAngleHand(
        45,
        axisLength: 30,
        axisGap: 20,
        landmarkOverrides: const {HandLandmarkType.thumbMCP: Offset(45, 94)},
      );

      expect(_detect(detector, hand), ZoomDirection.none);
      expect(detector.pendingDirection, ZoomDirection.zoomOut);

      now = now.add(const Duration(seconds: 1));
      expect(_detect(detector, hand), ZoomDirection.zoomOut);
    });

    test('a tucked close pinch stays neutral instead of becoming zoom in', () {
      final hand = _legacyAngleHand(
        45,
        axisLength: 30,
        axisGap: 20,
        landmarkOverrides: const {
          HandLandmarkType.thumbIP: Offset(108.8, 171.2),
        },
      );

      expect(_detect(detector, hand), ZoomDirection.none);
      expect(detector.pendingDirection, ZoomDirection.none);
    });

    test('an indeterminate tucked pinch cannot fall through to zoom in', () {
      final hand = _legacyAngleHand(
        45,
        axisLength: 30,
        axisGap: 20,
        missingTypes: const {HandLandmarkType.thumbMCP},
      );

      expect(_detect(detector, hand), ZoomDirection.none);
      expect(detector.pendingDirection, ZoomDirection.none);
    });

    test('an angled pinch at the exact closed boundary is zoom out', () {
      final hand = _rightAngleHandWithTipDistance(
        HandGestureThresholds.zoomClosedMaxDistanceRatio * 200,
      );

      expect(_detect(detector, hand), ZoomDirection.none);
      expect(detector.pendingDirection, ZoomDirection.zoomOut);
    });

    test('an angled pinch inside the distance dead band stays neutral', () {
      final hand = _rightAngleHandWithTipDistance(40);

      expect(_detect(detector, hand), ZoomDirection.none);
      expect(detector.pendingDirection, ZoomDirection.none);
    });

    test('an angled pinch at the open boundary is zoom in', () {
      final hand = _angleHand(
        90,
        axisLength: 10,
        indexAboveThumbGap: 4,
        tipDistance: HandGestureThresholds.zoomInMinDistanceRatio * 200,
      );

      expect(_detect(detector, hand), ZoomDirection.none);
      expect(detector.pendingDirection, ZoomDirection.zoomIn);
    });

    test('accepts an exact 2% index-above-thumb gap', () {
      final hand = _angleHand(60, indexAboveThumbGap: 4);

      expect(_detect(detector, hand), ZoomDirection.none);
      expect(detector.pendingDirection, ZoomDirection.zoomIn);
    });

    test('rejects a vertical gap just below 2%', () {
      final hand = _angleHand(60, indexAboveThumbGap: 3.9);

      expect(_detect(detector, hand), ZoomDirection.none);
      expect(detector.pendingDirection, ZoomDirection.none);
    });

    test('rejects equal-height fingertip segments', () {
      final hand = _angleHand(60, indexAboveThumbGap: 0);

      expect(_detect(detector, hand), ZoomDirection.none);
      expect(detector.pendingDirection, ZoomDirection.none);
    });

    test('rejects a fingertip segment below the thumb segment', () {
      final hand = _angleHand(60, indexAboveThumbGap: -5);

      expect(_detect(detector, hand), ZoomDirection.none);
      expect(detector.pendingDirection, ZoomDirection.none);
    });

    test('proximal thumb and index landmarks do not change the tip angle', () {
      final hand = _angleHand(
        90,
        landmarkOverrides: const {
          HandLandmarkType.thumbCMC: Offset(150, 90),
          HandLandmarkType.thumbMCP: Offset(150, 90),
          HandLandmarkType.indexFingerMCP: Offset(150, 90),
          HandLandmarkType.indexFingerPIP: Offset(150, 90),
          HandLandmarkType.middleFingerDIP: Offset(150, 90),
        },
      );

      expect(_detect(detector, hand), ZoomDirection.none);
      expect(detector.pendingDirection, ZoomDirection.zoomIn);
    });

    test('non-palm proximal thumb and index joints are not required', () {
      final hand = _angleHand(
        90,
        missingTypes: const {
          HandLandmarkType.thumbCMC,
          HandLandmarkType.thumbMCP,
          HandLandmarkType.indexFingerPIP,
        },
      );

      expect(_detect(detector, hand), ZoomDirection.none);
      expect(detector.pendingDirection, ZoomDirection.zoomIn);
    });

    test('zoom in does not require a visible index PIP landmark', () {
      for (final hand in [
        _zoomHand(
          tipDistance: 80,
          missingTypes: const {HandLandmarkType.indexFingerPIP},
        ),
        _zoomHand(
          tipDistance: 80,
          lowVisibilityTypes: const {HandLandmarkType.indexFingerPIP},
        ),
      ]) {
        detector.clearState();
        expect(_detect(detector, hand), ZoomDirection.none);
        expect(detector.pendingDirection, ZoomDirection.zoomIn);
      }
    });

    test('zoom in requires visible wrist, index MCP, and pinky MCP', () {
      for (final type in const {
        HandLandmarkType.wrist,
        HandLandmarkType.indexFingerMCP,
        HandLandmarkType.pinkyMCP,
      }) {
        detector.clearState();
        final hand = _angleHand(90, missingTypes: {type});

        expect(_detect(detector, hand), ZoomDirection.none);
        expect(detector.pendingDirection, ZoomDirection.none);
      }
    });

    test('requires the four fingertip-segment points 3, 4, 7, and 8', () {
      for (final type in const {
        HandLandmarkType.thumbIP,
        HandLandmarkType.thumbTip,
        HandLandmarkType.indexFingerDIP,
        HandLandmarkType.indexFingerTip,
      }) {
        detector.clearState();
        final hand = _angleHand(90, missingTypes: {type});

        expect(_detect(detector, hand), ZoomDirection.none);
        expect(detector.pendingDirection, ZoomDirection.none);
      }
    });

    test('rejects a zero-length visible fingertip segment', () {
      final hand = _angleHand(
        60,
        landmarkOverrides: const {
          HandLandmarkType.thumbIP: Offset(100, 100),
          HandLandmarkType.thumbTip: Offset(100, 100),
        },
      );

      expect(_detect(detector, hand), ZoomDirection.none);
      expect(detector.pendingDirection, ZoomDirection.none);
    });

    test('requires middle, ring, and pinky to stay folded', () {
      final hand = _zoomHand(tipDistance: 80, otherFingersFolded: false);

      expect(_detect(detector, hand), ZoomDirection.none);
      expect(detector.pendingDirection, ZoomDirection.none);
    });
  });

  group('ZoomGestureDetector hold resets', () {
    late DateTime now;
    late ZoomGestureDetector detector;

    setUp(() {
      now = DateTime(2026, 7, 18, 11);
      detector = ZoomGestureDetector(now: () => now);
    });

    test('hand loss resets immediately', () {
      final hand = _zoomHand(tipDistance: 80);

      expect(_detect(detector, hand), ZoomDirection.none);
      now = now.add(const Duration(milliseconds: 800));
      expect(
        _detect(detector, _zoomHand(tipDistance: 80, score: 0.2)),
        ZoomDirection.none,
      );
      expect(detector.isGestureActive, isFalse);

      now = now.add(const Duration(milliseconds: 200));
      expect(_detect(detector, hand), ZoomDirection.none);
      now = now.add(const Duration(seconds: 1));
      expect(_detect(detector, hand), ZoomDirection.zoomIn);
    });

    test('turning to the back side resets a zoom-out hold', () {
      final palm = _zoomOutHand();
      final back = _zoomOutHand(mirrorPose: true);

      expect(_detect(detector, palm), ZoomDirection.none);
      now = now.add(const Duration(milliseconds: 800));
      expect(_detect(detector, back), ZoomDirection.none);
      expect(detector.pendingDirection, ZoomDirection.none);
      expect(detector.isGestureActive, isFalse);

      expect(_detect(detector, palm), ZoomDirection.none);
      now = now.add(const Duration(milliseconds: 999));
      expect(_detect(detector, palm), ZoomDirection.none);
      now = now.add(const Duration(milliseconds: 1));
      expect(_detect(detector, palm), ZoomDirection.zoomOut);
    });

    test('turning to the back side clears an armed opening transition', () {
      final palm = _zoomOutHand();
      final back = _zoomOutHand(mirrorPose: true);

      expect(_detect(detector, palm), ZoomDirection.none);
      now = now.add(const Duration(seconds: 1));
      expect(_detect(detector, palm), ZoomDirection.zoomOut);
      expect(detector.reservesZoomInOpeningTransition, isTrue);

      expect(_detect(detector, back), ZoomDirection.none);
      expect(detector.pendingDirection, ZoomDirection.none);
      expect(detector.reservesZoomInOpeningTransition, isFalse);
    });

    test('clearState requires a fresh hold', () {
      final hand = _zoomOutHand();

      expect(_detect(detector, hand), ZoomDirection.none);
      now = now.add(const Duration(milliseconds: 800));
      detector.clearState();
      expect(detector.pendingDirection, ZoomDirection.none);
      expect(detector.hasZoomInDebugPose, isFalse);

      expect(_detect(detector, hand), ZoomDirection.none);
      now = now.add(const Duration(seconds: 1));
      expect(_detect(detector, hand), ZoomDirection.zoomOut);
    });

    test('clock rollback restarts the timer', () {
      final hand = _zoomHand(tipDistance: 80);

      expect(_detect(detector, hand), ZoomDirection.none);
      now = now.add(const Duration(milliseconds: 800));
      expect(_detect(detector, hand), ZoomDirection.none);

      now = now.subtract(const Duration(seconds: 2));
      expect(_detect(detector, hand), ZoomDirection.none);
      now = now.add(const Duration(milliseconds: 999));
      expect(_detect(detector, hand), ZoomDirection.none);
      now = now.add(const Duration(milliseconds: 1));
      expect(_detect(detector, hand), ZoomDirection.zoomIn);
    });

    test('losing the required fingertip separation resets the timer', () {
      final validHand = _angleHand(90);
      final invalidHand = _angleHand(30);

      expect(_detect(detector, validHand), ZoomDirection.none);
      now = now.add(const Duration(milliseconds: 800));
      expect(_detect(detector, invalidHand), ZoomDirection.none);
      expect(detector.pendingDirection, ZoomDirection.none);

      expect(_detect(detector, validHand), ZoomDirection.none);
      now = now.add(const Duration(seconds: 1));
      expect(_detect(detector, validHand), ZoomDirection.zoomIn);
    });

    test('losing the vertical gap resets the timer', () {
      final validHand = _angleHand(60);
      final invalidHand = _angleHand(60, indexAboveThumbGap: 0);

      expect(_detect(detector, validHand), ZoomDirection.none);
      now = now.add(const Duration(milliseconds: 800));
      expect(_detect(detector, invalidHand), ZoomDirection.none);
      expect(detector.pendingDirection, ZoomDirection.none);

      expect(_detect(detector, validHand), ZoomDirection.none);
      now = now.add(const Duration(seconds: 1));
      expect(_detect(detector, validHand), ZoomDirection.zoomIn);
    });

    test('excessive palm movement restarts the timer', () {
      expect(_detect(detector, _zoomHand(tipDistance: 80)), ZoomDirection.none);
      now = now.add(const Duration(milliseconds: 800));
      final moved = _zoomHand(tipDistance: 80, offset: const Offset(40, 0));
      expect(_detect(detector, moved), ZoomDirection.none);

      now = now.add(const Duration(milliseconds: 999));
      expect(_detect(detector, moved), ZoomDirection.none);
      now = now.add(const Duration(milliseconds: 1));
      expect(_detect(detector, moved), ZoomDirection.zoomIn);
    });

    test('two unstable folded fingers restart the timer', () {
      expect(_detect(detector, _zoomHand(tipDistance: 80)), ZoomDirection.none);
      now = now.add(const Duration(milliseconds: 800));
      final movedHand = _zoomHand(
        tipDistance: 80,
        fingerTipOffsets: const {
          HandLandmarkType.middleFingerTip: Offset(20, 0),
          HandLandmarkType.ringFingerTip: Offset(20, 0),
        },
      );
      expect(_detect(detector, movedHand), ZoomDirection.none);

      now = now.add(const Duration(seconds: 1));
      expect(_detect(detector, movedHand), ZoomDirection.zoomIn);
    });

    test('one unstable folded finger still allows the hold', () {
      expect(_detect(detector, _zoomHand(tipDistance: 80)), ZoomDirection.none);
      now = now.add(const Duration(seconds: 1));
      expect(
        _detect(
          detector,
          _zoomHand(
            tipDistance: 80,
            fingerTipOffsets: const {
              HandLandmarkType.middleFingerTip: Offset(20, 0),
            },
          ),
        ),
        ZoomDirection.zoomIn,
      );
    });
  });

  group('ZoomGestureDetector validation', () {
    test('rejects low-confidence and non-finite hands', () {
      final detector = ZoomGestureDetector();

      expect(
        _detect(detector, _zoomHand(tipDistance: 80, score: 0.2)),
        ZoomDirection.none,
      );
      expect(
        _detect(detector, _zoomHand(tipDistance: 80, score: double.nan)),
        ZoomDirection.none,
      );
      expect(detector.isGestureActive, isFalse);
    });

    test('rejects low-visibility required landmarks', () {
      final detector = ZoomGestureDetector();
      final hand = _zoomHand(
        tipDistance: 80,
        lowVisibilityTypes: const {HandLandmarkType.ringFingerTip},
      );

      expect(_detect(detector, hand), ZoomDirection.none);
      expect(detector.isGestureActive, isFalse);
    });

    test('rejects invalid image dimensions', () {
      final detector = ZoomGestureDetector();

      expect(
        detector.detect(
          hand: _zoomHand(tipDistance: 80),
          imageSize: const Size(double.nan, 400),
          mirrorHorizontally: false,
        ),
        ZoomDirection.none,
      );
      expect(detector.isGestureActive, isFalse);
    });
  });
}

ZoomDirection _detect(
  ZoomGestureDetector detector,
  Hand hand, {
  bool mirrorHorizontally = false,
}) {
  return detector.detect(
    hand: hand,
    imageSize: _imageSize,
    mirrorHorizontally: mirrorHorizontally,
  );
}

Hand _angleHand(
  double angleDegrees, {
  double axisLength = 30,
  double indexAboveThumbGap = 12,
  double? tipDistance,
  Map<HandLandmarkType, Offset> landmarkOverrides = const {},
  Set<HandLandmarkType> missingTypes = const {},
  bool mirrorRayGeometry = false,
  Offset rayOffset = Offset.zero,
}) {
  const intersection = Offset(300, 300);
  final halfAngleRadians = angleDegrees * math.pi / 360;
  final thumbRayAngle = math.pi / 2 - halfAngleRadians;
  final indexRayAngle = math.pi / 2 + halfAngleRadians;
  final thumbRay = Offset(math.cos(thumbRayAngle), math.sin(thumbRayAngle));
  final indexRay = Offset(math.cos(indexRayAngle), math.sin(indexRayAngle));

  final verticalFactor = math.cos(halfAngleRadians);
  final horizontalFactor = math.sin(halfAngleRadians);
  final distanceDifference = verticalFactor.abs() <= 1e-12
      ? 0.0
      : indexAboveThumbGap / verticalFactor;
  final distanceSum = tipDistance == null
      ? 140.0 + distanceDifference
      : math.sqrt(
              math.max(
                0,
                tipDistance * tipDistance -
                    indexAboveThumbGap * indexAboveThumbGap,
              ),
            ) /
            horizontalFactor;
  final indexRayDistance = (distanceSum + distanceDifference) / 2;
  final thumbRayDistance = (distanceSum - distanceDifference) / 2;

  final thumbTip = intersection - thumbRay * thumbRayDistance;
  final thumbIp = thumbTip + thumbRay * axisLength;
  final indexTip = intersection - indexRay * indexRayDistance;
  final indexDip = indexTip + indexRay * axisLength;

  Offset orientRayPoint(Offset point) {
    final oriented = mirrorRayGeometry
        ? Offset(220 - point.dx, point.dy)
        : point;
    return oriented + rayOffset;
  }

  return _zoomHand(
    tipDistance: 80,
    missingTypes: missingTypes,
    landmarkOverrides: {
      HandLandmarkType.thumbIP: orientRayPoint(thumbIp),
      HandLandmarkType.thumbTip: orientRayPoint(thumbTip),
      HandLandmarkType.indexFingerDIP: orientRayPoint(indexDip),
      HandLandmarkType.indexFingerTip: orientRayPoint(indexTip),
      ...landmarkOverrides,
    },
  );
}

Hand _parallelZoomInHand({
  double angleDegrees = 0,
  bool reverseIndexRay = false,
  bool pointLeft = false,
}) {
  const thumbTip = Offset(60, 90);
  const thumbRay = Offset(20, 30);
  const indexTip = Offset(150, 50);
  final thumbRayAngle = math.atan2(thumbRay.dy, thumbRay.dx);
  final indexRayAngle =
      thumbRayAngle +
      angleDegrees * math.pi / 180 +
      (reverseIndexRay ? math.pi : 0);
  final indexRay =
      Offset(math.cos(indexRayAngle), math.sin(indexRayAngle)) *
      thumbRay.distance;

  Offset orientRayPoint(Offset point) {
    return pointLeft ? Offset(220 - point.dx, point.dy) : point;
  }

  return _zoomHand(
    tipDistance: 80,
    landmarkOverrides: {
      HandLandmarkType.thumbIP: orientRayPoint(thumbTip + thumbRay),
      HandLandmarkType.thumbTip: orientRayPoint(thumbTip),
      HandLandmarkType.indexFingerDIP: orientRayPoint(indexTip + indexRay),
      HandLandmarkType.indexFingerTip: orientRayPoint(indexTip),
    },
  );
}

Hand _closeParallelZoomInHand({required double lineSeparation}) {
  const thumbTip = Offset(60, 90);
  const thumbRay = Offset(20, 30);
  final unit = thumbRay / thumbRay.distance;
  final normal = Offset(-unit.dy, unit.dx);
  final indexTip = thumbTip - unit * 70 + normal * lineSeparation;

  return _zoomHand(
    tipDistance: 80,
    landmarkOverrides: {
      HandLandmarkType.thumbIP: thumbTip + thumbRay,
      HandLandmarkType.thumbTip: thumbTip,
      HandLandmarkType.indexFingerDIP: indexTip + thumbRay,
      HandLandmarkType.indexFingerTip: indexTip,
    },
  );
}

Hand _legacyAngleHand(
  double angleDegrees, {
  double axisLength = 60,
  double axisGap = 100,
  Map<HandLandmarkType, Offset> landmarkOverrides = const {},
  Set<HandLandmarkType> missingTypes = const {},
}) {
  final indexDip = const Offset(150, 150);
  final indexTip = indexDip + const Offset(0, -1) * axisLength;
  final thumbIp = Offset(150 - axisGap, 150);
  final radians = (-90 + angleDegrees) * math.pi / 180;
  final thumbTip =
      thumbIp + Offset(math.cos(radians), math.sin(radians)) * axisLength;

  return _zoomHand(
    tipDistance: 80,
    missingTypes: missingTypes,
    landmarkOverrides: {
      HandLandmarkType.thumbIP: thumbIp,
      HandLandmarkType.thumbTip: thumbTip,
      HandLandmarkType.indexFingerDIP: indexDip,
      HandLandmarkType.indexFingerTip: indexTip,
      ...landmarkOverrides,
    },
  );
}

Hand _rightAngleHandWithTipDistance(double tipDistance) {
  const axisLength = 30.0;
  final horizontalDistance = math.sqrt(
    tipDistance * tipDistance - axisLength * axisLength,
  );

  return _legacyAngleHand(
    90,
    axisLength: axisLength,
    axisGap: axisLength + horizontalDistance,
    landmarkOverrides: const {HandLandmarkType.thumbMCP: Offset(45, 94)},
  );
}

Hand _zoomHandWithDistalIndexAngle(double angleDegrees) {
  const indexDip = Offset(170, 85);
  const indexTip = Offset(150, 70);
  const pipRayLength = 25.0;
  final tipRayAngle = math.atan2(
    indexTip.dy - indexDip.dy,
    indexTip.dx - indexDip.dx,
  );
  final pipRayAngle = tipRayAngle + angleDegrees * math.pi / 180;
  final indexPip =
      indexDip +
      Offset(math.cos(pipRayAngle), math.sin(pipRayAngle)) * pipRayLength;

  return _zoomHand(
    tipDistance: 80,
    landmarkOverrides: {HandLandmarkType.indexFingerPIP: indexPip},
  );
}

Hand _zoomOutHand({
  Offset offset = Offset.zero,
  double zOffset = 0,
  bool mirrorPose = false,
  Set<HandLandmarkType> missingTypes = const {},
  Set<HandLandmarkType> lowVisibilityTypes = const {},
  Handedness? handedness = Handedness.right,
}) {
  return _zoomHand(
    tipDistance: 20,
    offset: offset,
    zOffset: zOffset,
    mirrorPose: mirrorPose,
    missingTypes: missingTypes,
    lowVisibilityTypes: lowVisibilityTypes,
    handedness: handedness,
    landmarkOverrides: const {
      HandLandmarkType.thumbMCP: Offset(45, 94),
      HandLandmarkType.thumbIP: Offset(72, 82),
      HandLandmarkType.indexFingerDIP: Offset(125, 77),
      HandLandmarkType.indexFingerTip: Offset(120, 67),
    },
  );
}

Hand _touchingZoomOutHand({
  Map<HandLandmarkType, double> landmarkZOverrides = const {},
}) {
  return _zoomHand(
    tipDistance: 0,
    landmarkZOverrides: landmarkZOverrides,
    landmarkOverrides: const {
      HandLandmarkType.thumbMCP: Offset(45, 94),
      HandLandmarkType.thumbIP: Offset(90, 80),
      HandLandmarkType.thumbTip: Offset(110, 70),
      HandLandmarkType.indexFingerDIP: Offset(110, 50),
      HandLandmarkType.indexFingerTip: Offset(110, 70),
    },
  );
}

Hand _zoomHand({
  required double tipDistance,
  Offset offset = Offset.zero,
  double zOffset = 0,
  bool otherFingersFolded = true,
  Map<HandLandmarkType, Offset> fingerTipOffsets = const {},
  Map<HandLandmarkType, Offset> landmarkOverrides = const {},
  Map<HandLandmarkType, double> landmarkZOverrides = const {},
  double rotationDegrees = 0,
  bool mirrorPose = false,
  Set<HandLandmarkType> missingTypes = const {},
  Set<HandLandmarkType> lowVisibilityTypes = const {},
  double score = 1,
  Handedness? handedness = Handedness.right,
}) {
  final rotationRadians = rotationDegrees * math.pi / 180;
  final halfVector = const Offset(1, 0) * (tipDistance / 2);
  const tipCenter = Offset(110, 70);
  const poseCenter = Offset(110, 120);
  final landmarks = <HandLandmark>[];

  Offset transform(Offset point) {
    final sourceX = point.dx - poseCenter.dx;
    final sourceY = point.dy - poseCenter.dy;
    final rotatedX =
        sourceX * math.cos(rotationRadians) -
        sourceY * math.sin(rotationRadians);
    final rotatedY =
        sourceX * math.sin(rotationRadians) +
        sourceY * math.cos(rotationRadians);

    return Offset(
      poseCenter.dx + (mirrorPose ? -rotatedX : rotatedX) + offset.dx,
      poseCenter.dy + rotatedY + offset.dy,
    );
  }

  void add(HandLandmarkType type, Offset point) {
    if (missingTypes.contains(type)) return;

    final transformedPoint = transform(landmarkOverrides[type] ?? point);
    landmarks.add(
      HandLandmark(
        type: type,
        x: transformedPoint.dx,
        y: transformedPoint.dy,
        z: landmarkZOverrides[type] ?? zOffset,
        visibility: lowVisibilityTypes.contains(type) ? 0.2 : 1,
      ),
    );
  }

  add(HandLandmarkType.wrist, const Offset(100, 175));
  add(HandLandmarkType.thumbCMC, const Offset(85, 145));
  add(HandLandmarkType.thumbMCP, const Offset(120, 120));
  add(HandLandmarkType.thumbIP, const Offset(130, 110));
  add(HandLandmarkType.indexFingerMCP, const Offset(100, 120));
  add(HandLandmarkType.indexFingerPIP, const Offset(105, 95));
  add(HandLandmarkType.indexFingerDIP, const Offset(170, 85));
  add(HandLandmarkType.indexFingerTip, tipCenter + halfVector);

  _addFoldedFinger(
    add,
    mcp: HandLandmarkType.middleFingerMCP,
    pip: HandLandmarkType.middleFingerPIP,
    dip: HandLandmarkType.middleFingerDIP,
    tip: HandLandmarkType.middleFingerTip,
    x: 115,
    folded: otherFingersFolded,
    tipOffset:
        fingerTipOffsets[HandLandmarkType.middleFingerTip] ?? Offset.zero,
  );
  _addFoldedFinger(
    add,
    mcp: HandLandmarkType.ringFingerMCP,
    pip: HandLandmarkType.ringFingerPIP,
    dip: HandLandmarkType.ringFingerDIP,
    tip: HandLandmarkType.ringFingerTip,
    x: 130,
    folded: otherFingersFolded,
    tipOffset: fingerTipOffsets[HandLandmarkType.ringFingerTip] ?? Offset.zero,
  );
  _addFoldedFinger(
    add,
    mcp: HandLandmarkType.pinkyMCP,
    pip: HandLandmarkType.pinkyPIP,
    dip: HandLandmarkType.pinkyDIP,
    tip: HandLandmarkType.pinkyTip,
    x: 145,
    folded: otherFingersFolded,
    tipOffset: fingerTipOffsets[HandLandmarkType.pinkyTip] ?? Offset.zero,
  );

  add(HandLandmarkType.thumbTip, tipCenter - halfVector);

  return Hand(
    boundingBox: BoundingBox.ltrb(
      offset.dx,
      offset.dy,
      offset.dx + 200,
      offset.dy + 200,
    ),
    score: score,
    landmarks: landmarks,
    imageWidth: _imageSize.width.toInt(),
    imageHeight: _imageSize.height.toInt(),
    handedness: handedness,
  );
}

void _addFoldedFinger(
  void Function(HandLandmarkType type, Offset point) add, {
  required HandLandmarkType mcp,
  required HandLandmarkType pip,
  required HandLandmarkType dip,
  required HandLandmarkType tip,
  required double x,
  required bool folded,
  Offset tipOffset = Offset.zero,
}) {
  add(mcp, Offset(x, 120));
  add(pip, Offset(x, 145));
  add(dip, Offset(x + (folded ? 5 : 0), folded ? 135 : 168));
  add(tip, Offset(x, folded ? 125 : 190) + tipOffset);
}
