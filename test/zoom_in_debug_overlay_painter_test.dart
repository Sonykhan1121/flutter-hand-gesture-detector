import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gesture_detector/hand_gesture_features/presentation/painters/zoom_in_debug_overlay_painter.dart';
import 'package:hand_detection/hand_detection.dart';

void main() {
  testWidgets('renders accepted Zoom In rays without an exception', (
    tester,
  ) async {
    final painter = ZoomInDebugOverlayPainter(
      hand: _zoomInHand(),
      imageSize: const Size(200, 200),
      mirrorHorizontally: false,
    );

    await tester.pumpWidget(
      Center(
        child: CustomPaint(size: const Size(300, 300), painter: painter),
      ),
    );

    expect(tester.takeException(), isNull);
    expect(painter.shouldRepaint(painter), isFalse);
    expect(
      painter.shouldRepaint(
        ZoomInDebugOverlayPainter(
          hand: _zoomInHand(),
          imageSize: const Size(200, 200),
          mirrorHorizontally: true,
        ),
      ),
      isTrue,
    );
  });

  testWidgets('ignores a hand missing a required Zoom In ray point', (
    tester,
  ) async {
    await tester.pumpWidget(
      CustomPaint(
        size: const Size(300, 300),
        painter: ZoomInDebugOverlayPainter(
          hand: _zoomInHand(includeIndexTip: false),
          imageSize: const Size(200, 200),
          mirrorHorizontally: false,
        ),
      ),
    );

    expect(tester.takeException(), isNull);
  });

  for (final rayCase in _RayDebugCase.values) {
    testWidgets('renders ${rayCase.name} Zoom In geometry', (tester) async {
      await tester.pumpWidget(
        CustomPaint(
          size: const Size(300, 300),
          painter: ZoomInDebugOverlayPainter(
            hand: _zoomInHand(rayCase: rayCase),
            imageSize: const Size(200, 200),
            mirrorHorizontally: rayCase == _RayDebugCase.finiteMirrored,
          ),
        ),
      );

      expect(tester.takeException(), isNull);
    });
  }
}

enum _RayDebugCase { finite, finiteMirrored, distant, atInfinity }

Hand _zoomInHand({
  bool includeIndexTip = true,
  _RayDebugCase rayCase = _RayDebugCase.finite,
}) {
  late final Offset thumbIp;
  late final Offset thumbTip;
  late final Offset indexDip;
  late final Offset indexTip;
  switch (rayCase) {
    case _RayDebugCase.finite:
    case _RayDebugCase.finiteMirrored:
      thumbTip = const Offset(70, 70);
      thumbIp = const Offset(90, 100);
      indexTip = const Offset(150, 50);
      indexDip = const Offset(130, 80);
      break;
    case _RayDebugCase.distant:
      const farIntersection = Offset(1000, 1000);
      thumbTip = const Offset(70, 70);
      thumbIp = _pointToward(thumbTip, farIntersection, 30);
      indexTip = const Offset(150, 50);
      indexDip = _pointToward(indexTip, farIntersection, 30);
      break;
    case _RayDebugCase.atInfinity:
      thumbTip = const Offset(70, 70);
      thumbIp = const Offset(90, 100);
      indexTip = const Offset(150, 50);
      indexDip = const Offset(170, 80);
      break;
  }

  final landmarks = <HandLandmark>[
    _landmark(HandLandmarkType.thumbIP, thumbIp.dx, thumbIp.dy),
    _landmark(HandLandmarkType.thumbTip, thumbTip.dx, thumbTip.dy),
    _landmark(HandLandmarkType.indexFingerDIP, indexDip.dx, indexDip.dy),
    if (includeIndexTip)
      _landmark(HandLandmarkType.indexFingerTip, indexTip.dx, indexTip.dy),
  ];

  return Hand(
    boundingBox: BoundingBox.ltrb(0, 0, 200, 200),
    score: 1,
    landmarks: landmarks,
    imageWidth: 200,
    imageHeight: 200,
    handedness: Handedness.right,
  );
}

Offset _pointToward(Offset start, Offset target, double distance) {
  final direction = target - start;
  return start + direction / direction.distance * distance;
}

HandLandmark _landmark(HandLandmarkType type, double x, double y) {
  return HandLandmark(type: type, x: x, y: y, z: 0, visibility: 1);
}
