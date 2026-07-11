import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:gesture_detector/hand_gesture_features/domain/models/object_optical_flow_track_result.dart';
import 'package:gesture_detector/hand_gesture_features/domain/models/object_tracking_frame.dart';
import 'package:gesture_detector/hand_gesture_features/domain/services/object_optical_flow_tracker.dart';

void main() {
  group('ObjectOpticalFlowTracker', () {
    test('tracks a textured object translated between frames', () {
      final tracker = ObjectOpticalFlowTracker();
      addTearDown(tracker.dispose);
      final first = _texturedFrame(frameId: 1);
      final second = _texturedFrame(frameId: 2, dx: 4, dy: 2);
      const box = Rect.fromLTWH(0.25, 0.25, 0.40, 0.45);

      final seeded = tracker.seed(first, box);
      final tracked = tracker.update(second);

      expect(seeded.status, ObjectOpticalFlowTrackStatus.initialized);
      expect(
        tracked.status,
        ObjectOpticalFlowTrackStatus.tracked,
        reason:
            '${tracked.rejectionReason}; confidence=${tracked.confidence}; '
            'inliers=${tracked.inlierRatio}',
      );
      expect(tracked.displayBox.center.dx, greaterThan(box.center.dx));
      expect(tracked.displayBox.center.dy, greaterThan(box.center.dy));
      expect(tracked.validPointCount, greaterThanOrEqualTo(12));
      expect(tracked.inlierRatio, greaterThanOrEqualTo(0.60));
    });

    test('fails closed when the selected box has no usable features', () {
      final tracker = ObjectOpticalFlowTracker();
      addTearDown(tracker.dispose);
      final frame = ObjectTrackingFrame(
        frameId: 1,
        capturedAt: DateTime(2026),
        width: 120,
        height: 90,
        grayscaleBytes: Uint8List(120 * 90),
        rotation: null,
        mirrorHorizontally: false,
      );

      final result = tracker.seed(
        frame,
        const Rect.fromLTWH(0.25, 0.25, 0.40, 0.45),
      );

      expect(result.status, ObjectOpticalFlowTrackStatus.uncertain);
      expect(result.rejectionReason, 'not enough object features');
      expect(tracker.isActive, isFalse);
    });

    test('uses source-frame history for a delayed detector correction', () {
      final tracker = ObjectOpticalFlowTracker();
      addTearDown(tracker.dispose);
      final first = _texturedFrame(frameId: 10);
      final second = _texturedFrame(frameId: 11, dx: 4, dy: 2);
      const box = Rect.fromLTWH(0.25, 0.25, 0.40, 0.45);
      tracker.seed(first, box);
      final tracked = tracker.update(second);
      final correction = tracker.correctFromDetection(
        currentFrame: second,
        detectedFrameId: 10,
        detectedDisplayBox: box.shift(const Offset(0.04, 0)),
      );

      expect(correction, isNotNull);
      expect(correction!.isUsable, isTrue);
      expect(
        correction.displayBox.center.dx,
        greaterThan(tracked.displayBox.center.dx),
      );
    });

    test('rejects a large frame-to-frame jump instead of switching', () {
      final tracker = ObjectOpticalFlowTracker();
      addTearDown(tracker.dispose);
      tracker.seed(
        _texturedFrame(frameId: 1),
        const Rect.fromLTWH(0.25, 0.25, 0.40, 0.45),
      );

      final result = tracker.update(_texturedFrame(frameId: 2, dx: 32));

      expect(result.status, ObjectOpticalFlowTrackStatus.uncertain);
      expect(tracker.isActive, isFalse);
    });

    test('bounds source-frame history to twelve frames', () {
      final tracker = ObjectOpticalFlowTracker();
      addTearDown(tracker.dispose);
      const box = Rect.fromLTWH(0.25, 0.25, 0.40, 0.45);
      for (var frameId = 1; frameId <= 13; frameId++) {
        tracker.seed(_texturedFrame(frameId: frameId), box);
      }

      expect(tracker.displayBoxForFrame(1), isNull);
      expect(tracker.displayBoxForFrame(2), isNotNull);
      expect(tracker.displayBoxForFrame(13), isNotNull);
    });
  });
}

ObjectTrackingFrame _texturedFrame({
  required int frameId,
  int dx = 0,
  int dy = 0,
}) {
  const width = 120;
  const height = 90;
  final bytes = Uint8List(width * height);
  final random = math.Random(7);
  for (var y = 24; y < 63; y++) {
    for (var x = 31; x < 76; x++) {
      final targetX = x + dx;
      final targetY = y + dy;
      if (targetX < 0 || targetX >= width || targetY < 0 || targetY >= height) {
        continue;
      }
      final checker = ((x ~/ 4) + (y ~/ 4)).isEven ? 190 : 45;
      bytes[targetY * width + targetX] = (checker + random.nextInt(45)).clamp(
        0,
        255,
      );
    }
  }
  return ObjectTrackingFrame(
    frameId: frameId,
    capturedAt: DateTime(2026).add(Duration(milliseconds: frameId * 50)),
    width: width,
    height: height,
    grayscaleBytes: bytes,
    rotation: null,
    mirrorHorizontally: false,
  );
}
