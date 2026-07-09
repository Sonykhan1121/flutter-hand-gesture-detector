import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gesture_detector/hand_gesture_features/domain/constants/hand_gesture_thresholds.dart';
import 'package:gesture_detector/hand_gesture_features/domain/enums/zoom_direction.dart';
import 'package:gesture_detector/hand_gesture_features/domain/services/zoom_gesture_detector.dart';
import 'package:hand_detection/hand_detection.dart';

const _imageSize = Size(400, 400);

void main() {
  group('ZoomGestureDetector palm stability', () {
    test('does not arm zoom from non-finite hand confidence', () {
      var now = DateTime(2026);
      final detector = ZoomGestureDetector(now: () => now);

      expect(
        _detect(detector, _zoomHand(tipDistance: 20, score: double.infinity)),
        ZoomDirection.none,
      );
      expect(detector.isGestureActive, isFalse);

      now = now.add(HandGestureThresholds.zoomStartPoseHoldDuration);
      expect(_detect(detector, _zoomHand(tipDistance: 80)), ZoomDirection.none);
    });

    test('returns zoom in when pinch opens and palm stays stable', () {
      var now = DateTime(2026);
      final detector = ZoomGestureDetector(now: () => now);

      expect(_detect(detector, _zoomHand(tipDistance: 20)), ZoomDirection.none);

      now = now.add(HandGestureThresholds.zoomStartPoseHoldDuration);
      expect(_detect(detector, _zoomHand(tipDistance: 20)), ZoomDirection.none);

      now = now.add(HandGestureThresholds.zoomMinGestureDuration);
      expect(
        _detect(detector, _zoomHand(tipDistance: 80)),
        ZoomDirection.zoomIn,
      );
    });

    test('returns zoom in with reduced pinch-open distance', () {
      var now = DateTime(2026);
      final detector = ZoomGestureDetector(now: () => now);

      expect(_detect(detector, _zoomHand(tipDistance: 50)), ZoomDirection.none);

      now = now.add(HandGestureThresholds.zoomStartPoseHoldDuration);
      expect(_detect(detector, _zoomHand(tipDistance: 50)), ZoomDirection.none);

      now = now.add(HandGestureThresholds.zoomMinGestureDuration);
      expect(
        _detect(detector, _zoomHand(tipDistance: 55)),
        ZoomDirection.zoomIn,
      );
    });

    test('does not zoom in when the whole hand moves while pinch opens', () {
      var now = DateTime(2026);
      final detector = ZoomGestureDetector(now: () => now);

      expect(_detect(detector, _zoomHand(tipDistance: 20)), ZoomDirection.none);

      now = now.add(HandGestureThresholds.zoomStartPoseHoldDuration);
      expect(_detect(detector, _zoomHand(tipDistance: 20)), ZoomDirection.none);

      now = now.add(HandGestureThresholds.zoomMinGestureDuration);
      expect(
        _detect(
          detector,
          _zoomHand(tipDistance: 80, offset: const Offset(40, 0)),
        ),
        ZoomDirection.none,
      );
      expect(detector.isGestureActive, isFalse);
    });

    test('does not zoom in when the whole hand moves through depth', () {
      var now = DateTime(2026);
      final detector = ZoomGestureDetector(now: () => now);

      expect(_detect(detector, _zoomHand(tipDistance: 20)), ZoomDirection.none);

      now = now.add(HandGestureThresholds.zoomStartPoseHoldDuration);
      expect(_detect(detector, _zoomHand(tipDistance: 20)), ZoomDirection.none);

      now = now.add(HandGestureThresholds.zoomMinGestureDuration);
      expect(
        _detect(detector, _zoomHand(tipDistance: 80, zOffset: 120)),
        ZoomDirection.none,
      );
      expect(detector.isGestureActive, isFalse);
    });

    test('returns zoom out when pinch closes and palm stays stable', () {
      var now = DateTime(2026);
      final detector = ZoomGestureDetector(now: () => now);

      expect(_detect(detector, _zoomHand(tipDistance: 80)), ZoomDirection.none);

      now = now.add(HandGestureThresholds.zoomStartPoseHoldDuration);
      expect(_detect(detector, _zoomHand(tipDistance: 80)), ZoomDirection.none);

      now = now.add(HandGestureThresholds.zoomMinGestureDuration);
      expect(
        _detect(detector, _zoomHand(tipDistance: 20)),
        ZoomDirection.zoomOut,
      );
    });

    test('returns zoom out with reduced pinch-close distance', () {
      var now = DateTime(2026);
      final detector = ZoomGestureDetector(now: () => now);

      expect(_detect(detector, _zoomHand(tipDistance: 57)), ZoomDirection.none);

      now = now.add(HandGestureThresholds.zoomStartPoseHoldDuration);
      expect(_detect(detector, _zoomHand(tipDistance: 57)), ZoomDirection.none);

      now = now.add(HandGestureThresholds.zoomMinGestureDuration);
      expect(
        _detect(detector, _zoomHand(tipDistance: 51)),
        ZoomDirection.zoomOut,
      );
    });

    test('does not zoom out when the whole hand moves while pinch closes', () {
      var now = DateTime(2026);
      final detector = ZoomGestureDetector(now: () => now);

      expect(_detect(detector, _zoomHand(tipDistance: 80)), ZoomDirection.none);

      now = now.add(HandGestureThresholds.zoomStartPoseHoldDuration);
      expect(_detect(detector, _zoomHand(tipDistance: 80)), ZoomDirection.none);

      now = now.add(HandGestureThresholds.zoomMinGestureDuration);
      expect(
        _detect(
          detector,
          _zoomHand(tipDistance: 20, offset: const Offset(40, 0)),
        ),
        ZoomDirection.none,
      );
      expect(detector.isGestureActive, isFalse);
    });

    test('does not zoom in when two folded fingers move too much', () {
      var now = DateTime(2026);
      final detector = ZoomGestureDetector(now: () => now);

      expect(_detect(detector, _zoomHand(tipDistance: 20)), ZoomDirection.none);

      now = now.add(HandGestureThresholds.zoomStartPoseHoldDuration);
      expect(_detect(detector, _zoomHand(tipDistance: 20)), ZoomDirection.none);

      now = now.add(HandGestureThresholds.zoomMinGestureDuration);
      expect(
        _detect(
          detector,
          _zoomHand(
            tipDistance: 80,
            fingerTipOffsets: const {
              HandLandmarkType.middleFingerTip: Offset(20, 0),
              HandLandmarkType.ringFingerTip: Offset(20, 0),
            },
          ),
        ),
        ZoomDirection.none,
      );
      expect(detector.isGestureActive, isFalse);
    });

    test('does not zoom out when two folded fingers move too much', () {
      var now = DateTime(2026);
      final detector = ZoomGestureDetector(now: () => now);

      expect(_detect(detector, _zoomHand(tipDistance: 80)), ZoomDirection.none);

      now = now.add(HandGestureThresholds.zoomStartPoseHoldDuration);
      expect(_detect(detector, _zoomHand(tipDistance: 80)), ZoomDirection.none);

      now = now.add(HandGestureThresholds.zoomMinGestureDuration);
      expect(
        _detect(
          detector,
          _zoomHand(
            tipDistance: 20,
            fingerTipOffsets: const {
              HandLandmarkType.middleFingerTip: Offset(20, 0),
              HandLandmarkType.ringFingerTip: Offset(20, 0),
            },
          ),
        ),
        ZoomDirection.none,
      );
      expect(detector.isGestureActive, isFalse);
    });

    test('returns zoom in when only one folded finger moves too much', () {
      var now = DateTime(2026);
      final detector = ZoomGestureDetector(now: () => now);

      expect(_detect(detector, _zoomHand(tipDistance: 20)), ZoomDirection.none);

      now = now.add(HandGestureThresholds.zoomStartPoseHoldDuration);
      expect(_detect(detector, _zoomHand(tipDistance: 20)), ZoomDirection.none);

      now = now.add(HandGestureThresholds.zoomMinGestureDuration);
      expect(
        _detect(
          detector,
          _zoomHand(
            tipDistance: 80,
            fingerTipOffsets: const {HandLandmarkType.pinkyTip: Offset(20, 0)},
          ),
        ),
        ZoomDirection.zoomIn,
      );
    });

    test('returns partial zoom out when other fingers stay stable', () {
      var now = DateTime(2026);
      final detector = ZoomGestureDetector(now: () => now);

      expect(
        _detect(
          detector,
          _zoomHand(tipDistance: 80, otherFingersFolded: false),
          allowPartialZoomOut: true,
        ),
        ZoomDirection.none,
      );

      now = now.add(HandGestureThresholds.zoomStartPoseHoldDuration);
      expect(
        _detect(
          detector,
          _zoomHand(tipDistance: 80, otherFingersFolded: false),
          allowPartialZoomOut: true,
        ),
        ZoomDirection.none,
      );

      now = now.add(HandGestureThresholds.zoomMinGestureDuration);
      expect(
        _detect(
          detector,
          _zoomHand(tipDistance: 20, otherFingersFolded: false),
          allowPartialZoomOut: true,
        ),
        ZoomDirection.zoomOut,
      );
    });

    test('does not partial zoom out when two folded fingers move too much', () {
      var now = DateTime(2026);
      final detector = ZoomGestureDetector(now: () => now);

      expect(
        _detect(
          detector,
          _zoomHand(tipDistance: 80, otherFingersFolded: false),
          allowPartialZoomOut: true,
        ),
        ZoomDirection.none,
      );

      now = now.add(HandGestureThresholds.zoomStartPoseHoldDuration);
      expect(
        _detect(
          detector,
          _zoomHand(tipDistance: 80, otherFingersFolded: false),
          allowPartialZoomOut: true,
        ),
        ZoomDirection.none,
      );

      now = now.add(HandGestureThresholds.zoomMinGestureDuration);
      expect(
        _detect(
          detector,
          _zoomHand(
            tipDistance: 20,
            otherFingersFolded: false,
            fingerTipOffsets: const {
              HandLandmarkType.middleFingerTip: Offset(20, 0),
              HandLandmarkType.ringFingerTip: Offset(20, 0),
            },
          ),
          allowPartialZoomOut: true,
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
  bool allowPartialZoomOut = false,
}) {
  return detector.detect(
    hand: hand,
    imageSize: _imageSize,
    allowPartialZoomOut: allowPartialZoomOut,
  );
}

Hand _zoomHand({
  required double tipDistance,
  Offset offset = Offset.zero,
  double zOffset = 0,
  bool otherFingersFolded = true,
  Map<HandLandmarkType, Offset> fingerTipOffsets = const {},
  double score = 1,
}) {
  final halfDistance = tipDistance / 2;
  final landmarks = <HandLandmark>[];

  void add(HandLandmarkType type, double x, double y) {
    landmarks.add(
      HandLandmark(
        type: type,
        x: x + offset.dx,
        y: y + offset.dy,
        z: zOffset,
        visibility: 1,
      ),
    );
  }

  add(HandLandmarkType.wrist, 100, 175);

  add(HandLandmarkType.indexFingerMCP, 100, 120);
  add(HandLandmarkType.indexFingerTip, 110 + halfDistance, 70);

  _addFoldedFinger(
    add,
    mcp: HandLandmarkType.middleFingerMCP,
    pip: HandLandmarkType.middleFingerPIP,
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
    tip: HandLandmarkType.ringFingerTip,
    x: 130,
    folded: otherFingersFolded,
    tipOffset: fingerTipOffsets[HandLandmarkType.ringFingerTip] ?? Offset.zero,
  );
  _addFoldedFinger(
    add,
    mcp: HandLandmarkType.pinkyMCP,
    pip: HandLandmarkType.pinkyPIP,
    tip: HandLandmarkType.pinkyTip,
    x: 145,
    folded: otherFingersFolded,
    tipOffset: fingerTipOffsets[HandLandmarkType.pinkyTip] ?? Offset.zero,
  );

  add(HandLandmarkType.thumbTip, 110 - halfDistance, 70);

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
    handedness: Handedness.right,
  );
}

void _addFoldedFinger(
  void Function(HandLandmarkType type, double x, double y) add, {
  required HandLandmarkType mcp,
  required HandLandmarkType pip,
  required HandLandmarkType tip,
  required double x,
  required bool folded,
  Offset tipOffset = Offset.zero,
}) {
  add(mcp, x, 120);
  add(pip, x, 145);
  add(tip, x + tipOffset.dx, (folded ? 125 : 190) + tipOffset.dy);
}
