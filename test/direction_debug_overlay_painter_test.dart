import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gesture_detector/hand_gesture_features/domain/enums/hand_move_direction.dart';
import 'package:gesture_detector/hand_gesture_features/presentation/painters/direction_debug_overlay_painter.dart';
import 'package:hand_detection/hand_detection.dart';

void main() {
  for (final direction in HandMoveDirection.values) {
    testWidgets('renders the ${direction.name} full-screen direction axis', (
      tester,
    ) async {
      await tester.pumpWidget(
        Center(
          child: CustomPaint(
            size: const Size(320, 480),
            painter: DirectionDebugOverlayPainter(
              hand: _directionHand(),
              imageSize: const Size(200, 300),
              mirrorHorizontally: false,
              candidateDirection: direction,
              acceptedDirection: direction,
              debugSummary: 'direction: ${direction.name}',
            ),
          ),
        ),
      );

      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('supports mirrored recording-preview mapping', (tester) async {
    await tester.pumpWidget(
      CustomPaint(
        size: const Size(480, 320),
        painter: DirectionDebugOverlayPainter(
          hand: _directionHand(),
          imageSize: const Size(200, 300),
          mirrorHorizontally: true,
          candidateDirection: HandMoveDirection.down,
          acceptedDirection: HandMoveDirection.none,
          debugSummary: 'direction: hand settling 2/3; down pose',
          previewQuarterTurns: 3,
          useRecordingPreviewMapping: true,
        ),
      ),
    );

    expect(tester.takeException(), isNull);
  });

  testWidgets('still renders sector guides without a usable hand', (
    tester,
  ) async {
    await tester.pumpWidget(
      CustomPaint(
        size: const Size(300, 300),
        painter: const DirectionDebugOverlayPainter(
          hand: null,
          imageSize: Size(200, 200),
          mirrorHorizontally: false,
          candidateDirection: HandMoveDirection.none,
          acceptedDirection: HandMoveDirection.none,
          debugSummary: 'direction: no matching static direction',
        ),
      ),
    );

    expect(tester.takeException(), isNull);
  });

  testWidgets('handles unavailable angle geometry without throwing', (
    tester,
  ) async {
    await tester.pumpWidget(
      CustomPaint(
        size: const Size(320, 480),
        painter: DirectionDebugOverlayPainter(
          hand: _directionHand(includeAngleLandmarks: false),
          imageSize: const Size(200, 300),
          mirrorHorizontally: false,
          candidateDirection: HandMoveDirection.up,
          acceptedDirection: HandMoveDirection.none,
          debugSummary: 'direction: up rejected; missing angle points',
        ),
      ),
    );

    expect(tester.takeException(), isNull);
  });

  test('repaints when live direction debug inputs change', () {
    final painter = DirectionDebugOverlayPainter(
      hand: _directionHand(),
      imageSize: const Size(200, 300),
      mirrorHorizontally: false,
      candidateDirection: HandMoveDirection.right,
      acceptedDirection: HandMoveDirection.none,
      debugSummary: 'direction: confirming right 1/3',
    );

    expect(painter.shouldRepaint(painter), isFalse);
    expect(
      painter.shouldRepaint(
        DirectionDebugOverlayPainter(
          hand: painter.hand,
          imageSize: painter.imageSize,
          mirrorHorizontally: painter.mirrorHorizontally,
          candidateDirection: HandMoveDirection.right,
          acceptedDirection: HandMoveDirection.right,
          debugSummary: 'direction: static right',
        ),
      ),
      isTrue,
    );
  });

  test('repaints when visible checklist text changes', () {
    final painter = DirectionDebugOverlayPainter(
      hand: _directionHand(),
      imageSize: const Size(200, 300),
      mirrorHorizontally: false,
      candidateDirection: HandMoveDirection.left,
      acceptedDirection: HandMoveDirection.none,
      debugSummary: 'first hidden summary',
    );

    expect(
      painter.shouldRepaint(
        DirectionDebugOverlayPainter(
          hand: painter.hand,
          imageSize: painter.imageSize,
          mirrorHorizontally: painter.mirrorHorizontally,
          candidateDirection: painter.candidateDirection,
          acceptedDirection: painter.acceptedDirection,
          debugSummary: 'different hidden summary',
        ),
      ),
      isTrue,
    );
  });
}

Hand _directionHand({bool includeAngleLandmarks = true}) {
  return Hand(
    boundingBox: BoundingBox.ltrb(40, 60, 170, 270),
    score: 1,
    landmarks: [
      if (includeAngleLandmarks)
        HandLandmark(
          type: HandLandmarkType.wrist,
          x: 100,
          y: 265,
          z: 0,
          visibility: 1,
        ),
      HandLandmark(
        type: HandLandmarkType.indexFingerMCP,
        x: 80,
        y: 210,
        z: 0,
        visibility: 1,
      ),
      HandLandmark(
        type: HandLandmarkType.indexFingerPIP,
        x: 105,
        y: 170,
        z: 0,
        visibility: 1,
      ),
      if (includeAngleLandmarks)
        HandLandmark(
          type: HandLandmarkType.indexFingerDIP,
          x: 130,
          y: 130,
          z: 0,
          visibility: 1,
        ),
      HandLandmark(
        type: HandLandmarkType.indexFingerTip,
        x: 155,
        y: 90,
        z: 0,
        visibility: 1,
      ),
      if (includeAngleLandmarks) ...[
        HandLandmark(
          type: HandLandmarkType.middleFingerMCP,
          x: 100,
          y: 220,
          z: 0,
          visibility: 1,
        ),
        HandLandmark(
          type: HandLandmarkType.middleFingerPIP,
          x: 105,
          y: 190,
          z: 0,
          visibility: 1,
        ),
        HandLandmark(
          type: HandLandmarkType.middleFingerDIP,
          x: 115,
          y: 205,
          z: 0,
          visibility: 1,
        ),
        HandLandmark(
          type: HandLandmarkType.middleFingerTip,
          x: 110,
          y: 215,
          z: 0,
          visibility: 1,
        ),
        HandLandmark(
          type: HandLandmarkType.ringFingerMCP,
          x: 120,
          y: 225,
          z: 0,
          visibility: 1,
        ),
        HandLandmark(
          type: HandLandmarkType.ringFingerPIP,
          x: 125,
          y: 195,
          z: 0,
          visibility: 1,
        ),
        HandLandmark(
          type: HandLandmarkType.ringFingerDIP,
          x: 135,
          y: 210,
          z: 0,
          visibility: 1,
        ),
        HandLandmark(
          type: HandLandmarkType.ringFingerTip,
          x: 130,
          y: 220,
          z: 0,
          visibility: 1,
        ),
        HandLandmark(
          type: HandLandmarkType.pinkyMCP,
          x: 140,
          y: 230,
          z: 0,
          visibility: 1,
        ),
        HandLandmark(
          type: HandLandmarkType.pinkyPIP,
          x: 145,
          y: 200,
          z: 0,
          visibility: 1,
        ),
        HandLandmark(
          type: HandLandmarkType.pinkyDIP,
          x: 155,
          y: 215,
          z: 0,
          visibility: 1,
        ),
        HandLandmark(
          type: HandLandmarkType.pinkyTip,
          x: 150,
          y: 225,
          z: 0,
          visibility: 1,
        ),
      ],
    ],
    imageWidth: 200,
    imageHeight: 300,
    handedness: Handedness.right,
  );
}
