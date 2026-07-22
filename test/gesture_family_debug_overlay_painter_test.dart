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
        type: HandLandmarkType.thumbTip,
        x: 50,
        y: 170,
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
