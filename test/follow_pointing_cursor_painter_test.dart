import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gesture_detector/hand_gesture_features/presentation/painters/follow_pointing_cursor_painter.dart';

void main() {
  test(
    'pointing cursor paints progress and repaints when it changes',
    () async {
      const first = FollowPointingCursorPainter(
        realIndexTip: Offset(0.25, 0.50),
        projectedPoint: Offset(0.50, 0.50),
        progress: 0.5,
        isInFrame: true,
      );
      const same = FollowPointingCursorPainter(
        realIndexTip: Offset(0.25, 0.50),
        projectedPoint: Offset(0.50, 0.50),
        progress: 0.5,
        isInFrame: true,
      );
      const changed = FollowPointingCursorPainter(
        realIndexTip: Offset(0.75, 0.50),
        projectedPoint: Offset(1.0, 0.50),
        progress: 1,
        isInFrame: false,
        previewQuarterTurns: 1,
      );

      expect(first.shouldRepaint(same), isFalse);
      expect(changed.shouldRepaint(first), isTrue);

      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      first.paint(canvas, const Size(100, 100));
      final image = await recorder.endRecording().toImage(100, 100);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      expect(bytes, isNotNull);
      final centerPixel = (50 * 100 + 50) * 4;
      expect(bytes!.getUint8(centerPixel + 3), greaterThan(0));
    },
  );

  test('off-screen edge indicator and rotated guide paint safely', () async {
    const painter = FollowPointingCursorPainter(
      realIndexTip: Offset(0.60, 0.50),
      projectedPoint: Offset(1.0, 0.50),
      progress: 0,
      isInFrame: false,
      previewQuarterTurns: 1,
    );

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    painter.paint(canvas, const Size(100, 100));
    final image = await recorder.endRecording().toImage(100, 100);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.rawRgba);

    expect(bytes, isNotNull);
  });
}
