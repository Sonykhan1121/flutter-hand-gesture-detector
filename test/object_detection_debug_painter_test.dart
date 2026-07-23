import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gesture_detector/hand_gesture_features/domain/enums/follow_target_type.dart';
import 'package:gesture_detector/hand_gesture_features/domain/models/follow_target.dart';
import 'package:gesture_detector/hand_gesture_features/presentation/painters/object_detection_debug_painter.dart';

void main() {
  group('ObjectDetectionDebugPainter', () {
    testWidgets('renders face and object debug targets', (tester) async {
      final targets = [
        _target(
          type: FollowTargetType.face,
          displayBox: const Rect.fromLTWH(0.10, 0.10, 0.20, 0.20),
          label: 'Face',
        ),
        _target(
          type: FollowTargetType.object,
          displayBox: const Rect.fromLTWH(0.55, 0.45, 0.30, 0.30),
          label: 'Mobile stand',
        ),
      ];

      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: SizedBox(
            width: 320,
            height: 240,
            child: CustomPaint(
              painter: ObjectDetectionDebugPainter(targets: targets),
            ),
          ),
        ),
      );

      final customPaint = tester.widget<CustomPaint>(find.byType(CustomPaint));
      expect(customPaint.painter, isA<ObjectDetectionDebugPainter>());
    });

    test('repaints when painter inputs change', () {
      final targets = [
        _target(
          type: FollowTargetType.object,
          displayBox: const Rect.fromLTWH(0.20, 0.20, 0.20, 0.20),
          label: 'Object',
        ),
      ];

      final painter = ObjectDetectionDebugPainter(targets: targets);

      expect(
        painter.shouldRepaint(ObjectDetectionDebugPainter(targets: targets)),
        isFalse,
      );
      expect(
        painter.shouldRepaint(
          ObjectDetectionDebugPainter(targets: List.of(targets)),
        ),
        isTrue,
      );
      expect(
        painter.shouldRepaint(
          ObjectDetectionDebugPainter(
            targets: targets,
            labelPrefix: 'Release → ',
          ),
        ),
        isTrue,
      );
      expect(
        painter.shouldRepaint(
          ObjectDetectionDebugPainter(targets: targets, showLabels: false),
        ),
        isTrue,
      );
      expect(
        painter.shouldRepaint(
          ObjectDetectionDebugPainter(targets: targets, showCenters: true),
        ),
        isTrue,
      );
      expect(
        painter.shouldRepaint(
          ObjectDetectionDebugPainter(targets: targets, color: Colors.green),
        ),
        isTrue,
      );
      expect(
        painter.shouldRepaint(
          ObjectDetectionDebugPainter(targets: targets, previewQuarterTurns: 1),
        ),
        isTrue,
      );
    });

    test('draws an opt-in marker at the target rectangle center', () async {
      final target = _target(
        type: FollowTargetType.object,
        displayBox: const Rect.fromLTWH(0.20, 0.20, 0.40, 0.40),
        label: 'Object',
      );
      const size = Size(200, 200);

      final marked = await _pixelAt(
        ObjectDetectionDebugPainter(
          targets: [target],
          showLabels: false,
          showCenters: true,
          color: Colors.green,
        ),
        size: size,
        point: const Offset(80, 80),
      );
      final unmarked = await _pixelAt(
        ObjectDetectionDebugPainter(
          targets: [target],
          showLabels: false,
          color: Colors.green,
        ),
        size: size,
        point: const Offset(80, 80),
      );

      expect(marked.alpha, greaterThan(0));
      expect(marked.green, greaterThan(marked.red));
      expect(unmarked.alpha, 0);
    });
  });
}

Future<({int red, int green, int blue, int alpha})> _pixelAt(
  CustomPainter painter, {
  required Size size,
  required Offset point,
}) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  painter.paint(canvas, size);
  final image = await recorder.endRecording().toImage(
    size.width.toInt(),
    size.height.toInt(),
  );
  final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  image.dispose();
  if (data == null) return (red: 0, green: 0, blue: 0, alpha: 0);
  final offset =
      ((point.dy.toInt() * size.width.toInt()) + point.dx.toInt()) * 4;
  return (
    red: data.getUint8(offset),
    green: data.getUint8(offset + 1),
    blue: data.getUint8(offset + 2),
    alpha: data.getUint8(offset + 3),
  );
}

FollowTarget _target({
  required FollowTargetType type,
  required Rect displayBox,
  required String label,
}) {
  return FollowTarget(
    type: type,
    boundingBox: displayBox,
    displayBox: displayBox,
    detectedAt: DateTime(2026),
    label: label,
  );
}
