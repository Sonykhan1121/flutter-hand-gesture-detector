import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gesture_detector/hand_gesture_features/domain/enums/gesture_debug_mode.dart';
import 'package:gesture_detector/hand_gesture_features/domain/models/gesture_debug_evaluation.dart';
import 'package:gesture_detector/hand_gesture_features/presentation/painters/gesture_family_debug_overlay_painter.dart';
import 'package:hand_detection/hand_detection.dart';

void main() {
  for (final mode in const [
    GestureDebugMode.zoomIn,
    GestureDebugMode.zoomOut,
    GestureDebugMode.returnMain,
    GestureDebugMode.recording,
    GestureDebugMode.callMe,
    GestureDebugMode.followObject,
  ]) {
    testWidgets('renders only the $mode family snapshot without exception', (
      tester,
    ) async {
      final evaluation = GestureDebugEvaluation(
        title: mode.name,
        matches: false,
        requirements: const [
          GestureDebugRequirement(matches: true, text: 'visible check'),
          GestureDebugRequirement(matches: false, text: 'failed check'),
        ],
        landmarkTypes: const {
          HandLandmarkType.wrist,
          HandLandmarkType.thumbTip,
          HandLandmarkType.indexFingerTip,
          HandLandmarkType.pinkyTip,
        },
      );
      final painter = GestureFamilyDebugOverlayPainter(
        mode: mode,
        hand: _debugHand(),
        imageSize: const Size(200, 300),
        mirrorHorizontally: true,
        evaluation: evaluation,
        previewQuarterTurns: 1,
        useRecordingPreviewMapping: true,
      );

      await tester.pumpWidget(
        Center(
          child: CustomPaint(size: const Size(480, 320), painter: painter),
        ),
      );

      expect(tester.takeException(), isNull);
      expect(painter.shouldRepaint(painter), isFalse);
    });
  }

  test(
    'red enclosed touch-space fill is exclusive to Zoom Out debug',
    () async {
      final zoomOutRedPixels = await _redPixelCount(
        GestureDebugMode.zoomOut,
        tipsTouching: true,
      );
      final zoomInRedPixels = await _redPixelCount(
        GestureDebugMode.zoomIn,
        tipsTouching: true,
      );
      final openZoomOutRedPixels = await _redPixelCount(
        GestureDebugMode.zoomOut,
        tipsTouching: false,
      );

      expect(zoomOutRedPixels, greaterThan(50));
      expect(zoomInRedPixels, 0);
      expect(openZoomOutRedPixels, 0);
    },
  );

  test('Follow Object draws the selector hand bounding-box center', () async {
    final followObjectCenter = await _pixelAt(
      GestureDebugMode.followObject,
      const Offset(100, 155),
    );
    final callMeCenter = await _pixelAt(
      GestureDebugMode.callMe,
      const Offset(100, 155),
    );

    expect(followObjectCenter.alpha, greaterThan(0));
    expect(followObjectCenter.red, greaterThan(200));
    expect(followObjectCenter.green, greaterThan(150));
    expect(callMeCenter.alpha, 0);
  });
}

Future<({int red, int green, int blue, int alpha})> _pixelAt(
  GestureDebugMode mode,
  Offset point,
) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  final painter = GestureFamilyDebugOverlayPainter(
    mode: mode,
    hand: _debugHand(),
    imageSize: const Size(200, 300),
    mirrorHorizontally: false,
    evaluation: GestureDebugEvaluation(
      title: mode.name,
      matches: true,
      requirements: const [],
      landmarkTypes: const {},
    ),
  );
  painter.paint(canvas, const Size(200, 300));
  final image = await recorder.endRecording().toImage(200, 300);
  final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  image.dispose();
  if (data == null) return (red: 0, green: 0, blue: 0, alpha: 0);
  final offset = ((point.dy.toInt() * 200) + point.dx.toInt()) * 4;
  return (
    red: data.getUint8(offset),
    green: data.getUint8(offset + 1),
    blue: data.getUint8(offset + 2),
    alpha: data.getUint8(offset + 3),
  );
}

Future<int> _redPixelCount(
  GestureDebugMode mode, {
  required bool tipsTouching,
}) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  final painter = GestureFamilyDebugOverlayPainter(
    mode: mode,
    hand: _debugHand(),
    imageSize: const Size(200, 300),
    mirrorHorizontally: false,
    evaluation: GestureDebugEvaluation(
      title: mode.name,
      matches: true,
      requirements: [
        GestureDebugRequirement(
          id: GestureDebugRequirementId.zoomTipGap,
          matches: tipsTouching,
          text: 'tip gap',
        ),
      ],
      landmarkTypes: const {},
    ),
  );
  painter.paint(canvas, const Size(200, 300));
  final image = await recorder.endRecording().toImage(200, 300);
  final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  image.dispose();
  if (data == null) return 0;

  var count = 0;
  for (var offset = 0; offset < data.lengthInBytes; offset += 4) {
    final pixelIndex = offset ~/ 4;
    final y = pixelIndex ~/ 200;
    if (y < 70) continue;
    final red = data.getUint8(offset);
    final green = data.getUint8(offset + 1);
    final blue = data.getUint8(offset + 2);
    final alpha = data.getUint8(offset + 3);
    if (red > 200 && green < 140 && blue < 140 && alpha > 30) count += 1;
  }
  return count;
}

Hand _debugHand() {
  return Hand(
    boundingBox: BoundingBox.ltrb(20, 30, 180, 280),
    score: 1,
    landmarks: [
      HandLandmark(
        type: HandLandmarkType.wrist,
        x: 100,
        y: 270,
        z: 0,
        visibility: 1,
      ),
      HandLandmark(
        type: HandLandmarkType.thumbMCP,
        x: 72,
        y: 215,
        z: 0,
        visibility: 1,
      ),
      HandLandmark(
        type: HandLandmarkType.thumbIP,
        x: 60,
        y: 185,
        z: 0,
        visibility: 1,
      ),
      HandLandmark(
        type: HandLandmarkType.thumbTip,
        x: 50,
        y: 170,
        z: 0,
        visibility: 1,
      ),
      HandLandmark(
        type: HandLandmarkType.indexFingerMCP,
        x: 112,
        y: 215,
        z: 0,
        visibility: 1,
      ),
      HandLandmark(
        type: HandLandmarkType.indexFingerPIP,
        x: 96,
        y: 150,
        z: 0,
        visibility: 1,
      ),
      HandLandmark(
        type: HandLandmarkType.indexFingerDIP,
        x: 82,
        y: 100,
        z: 0,
        visibility: 1,
      ),
      HandLandmark(
        type: HandLandmarkType.indexFingerTip,
        x: 90,
        y: 60,
        z: 0,
        visibility: 1,
      ),
      HandLandmark(
        type: HandLandmarkType.pinkyTip,
        x: 160,
        y: 100,
        z: 0,
        visibility: 1,
      ),
    ],
    imageWidth: 200,
    imageHeight: 300,
    handedness: Handedness.right,
  );
}
