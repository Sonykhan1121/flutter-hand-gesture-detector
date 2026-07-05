import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gesture_detector/hand_gesture_features/domain/constants/hand_gesture_thresholds.dart';
import 'package:gesture_detector/hand_gesture_features/domain/enums/zoom_direction.dart';
import 'package:gesture_detector/hand_gesture_features/domain/services/zoom_gesture_detector.dart';
import 'package:hand_detection/hand_detection.dart';

const _imageSize = Size(400, 400);

void main() {
  group('ZoomGestureDetector palm stability', () {
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
  });
}

ZoomDirection _detect(ZoomGestureDetector detector, Hand hand) {
  return detector.detect(hand: hand, imageSize: _imageSize);
}

Hand _zoomHand({required double tipDistance, Offset offset = Offset.zero}) {
  final halfDistance = tipDistance / 2;
  final landmarks = <HandLandmark>[];

  void add(HandLandmarkType type, double x, double y) {
    landmarks.add(
      HandLandmark(
        type: type,
        x: x + offset.dx,
        y: y + offset.dy,
        z: 0,
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
  );
  _addFoldedFinger(
    add,
    mcp: HandLandmarkType.ringFingerMCP,
    pip: HandLandmarkType.ringFingerPIP,
    tip: HandLandmarkType.ringFingerTip,
    x: 130,
  );
  _addFoldedFinger(
    add,
    mcp: HandLandmarkType.pinkyMCP,
    pip: HandLandmarkType.pinkyPIP,
    tip: HandLandmarkType.pinkyTip,
    x: 145,
  );

  add(HandLandmarkType.thumbTip, 110 - halfDistance, 70);

  return Hand(
    boundingBox: BoundingBox.ltrb(
      offset.dx,
      offset.dy,
      offset.dx + 200,
      offset.dy + 200,
    ),
    score: 1,
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
}) {
  add(mcp, x, 120);
  add(pip, x, 145);
  add(tip, x, 125);
}
