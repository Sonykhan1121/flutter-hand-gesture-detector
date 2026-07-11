import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:gesture_detector/hand_gesture_features/domain/utils/camera_frame_box_mapper.dart';
import 'package:hand_detection/hand_detection.dart';

void main() {
  group('cameraFrameRectToDisplayBox', () {
    test('normalizes an unrotated raw camera box', () {
      final box = cameraFrameRectToDisplayBox(
        rect: const Rect.fromLTWH(100, 50, 200, 100),
        imageSize: const Size(1000, 500),
        rotation: null,
        mirrorHorizontally: false,
      );

      expect(box.left, closeTo(0.10, 0.0001));
      expect(box.top, closeTo(0.10, 0.0001));
      expect(box.right, closeTo(0.30, 0.0001));
      expect(box.bottom, closeTo(0.30, 0.0001));
    });

    test('rotates all raw box corners for portrait Android preview', () {
      final box = cameraFrameRectToDisplayBox(
        rect: const Rect.fromLTWH(560, 310, 160, 100),
        imageSize: const Size(1280, 720),
        rotation: CameraFrameRotation.cw90,
        mirrorHorizontally: false,
      );

      expect(box.center.dx, closeTo(0.50, 0.0001));
      expect(box.center.dy, closeTo(0.50, 0.0001));
      expect(box.left, closeTo(0.4306, 0.0001));
      expect(box.top, closeTo(0.4375, 0.0001));
      expect(box.right, closeTo(0.5694, 0.0001));
      expect(box.bottom, closeTo(0.5625, 0.0001));
    });

    test('mirrors after rotation for front-camera preview', () {
      final box = cameraFrameRectToDisplayBox(
        rect: const Rect.fromLTWH(100, 50, 200, 100),
        imageSize: const Size(1000, 500),
        rotation: null,
        mirrorHorizontally: true,
      );

      expect(box.left, closeTo(0.70, 0.0001));
      expect(box.right, closeTo(0.90, 0.0001));
      expect(box.top, closeTo(0.10, 0.0001));
      expect(box.bottom, closeTo(0.30, 0.0001));
    });
  });

  group('imageRectToDisplayBox', () {
    test('maps already-upright package detection boxes without rotation', () {
      final box = imageRectToDisplayBox(
        rect: const Rect.fromLTWH(64, 48, 128, 96),
        imageSize: const Size(640, 480),
        mirrorHorizontally: false,
      );

      expect(box.left, closeTo(0.10, 0.0001));
      expect(box.top, closeTo(0.10, 0.0001));
      expect(box.right, closeTo(0.30, 0.0001));
      expect(box.bottom, closeTo(0.30, 0.0001));
    });

    test('mirrors package detection boxes for front-camera preview', () {
      final box = imageRectToDisplayBox(
        rect: const Rect.fromLTWH(64, 48, 128, 96),
        imageSize: const Size(640, 480),
        mirrorHorizontally: true,
      );

      expect(box.left, closeTo(0.70, 0.0001));
      expect(box.right, closeTo(0.90, 0.0001));
      expect(box.top, closeTo(0.10, 0.0001));
      expect(box.bottom, closeTo(0.30, 0.0001));
    });
  });

  group('displayRectToCameraFrameRect', () {
    test('round-trips rotation and front-camera mirroring', () {
      const rawNormalized = Rect.fromLTRB(0.12, 0.20, 0.38, 0.62);

      for (final rotation in <CameraFrameRotation?>[
        null,
        ...CameraFrameRotation.values,
      ]) {
        for (final mirrored in [false, true]) {
          final display = cameraFrameRectToDisplayBox(
            rect: Rect.fromLTRB(
              rawNormalized.left * 1000,
              rawNormalized.top * 500,
              rawNormalized.right * 1000,
              rawNormalized.bottom * 500,
            ),
            imageSize: const Size(1000, 500),
            rotation: rotation,
            mirrorHorizontally: mirrored,
          );
          final restored = displayRectToCameraFrameRect(
            displayRect: display,
            rotation: rotation,
            mirrorHorizontally: mirrored,
          );

          expect(restored.left, closeTo(rawNormalized.left, 0.0001));
          expect(restored.top, closeTo(rawNormalized.top, 0.0001));
          expect(restored.right, closeTo(rawNormalized.right, 0.0001));
          expect(restored.bottom, closeTo(rawNormalized.bottom, 0.0001));
        }
      }
    });
  });
}
