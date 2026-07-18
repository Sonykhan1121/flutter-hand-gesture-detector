import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gesture_detector/hand_gesture_features/presentation/utils/ml_kit_preview_mapper.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:object_detection/object_detection.dart';

void main() {
  group('mlKitInputRotation', () {
    test('maps every camera-frame rotation', () {
      expect(mlKitInputRotation(null), InputImageRotation.rotation0deg);
      expect(
        mlKitInputRotation(CameraFrameRotation.cw90),
        InputImageRotation.rotation90deg,
      );
      expect(
        mlKitInputRotation(CameraFrameRotation.cw180),
        InputImageRotation.rotation180deg,
      );
      expect(
        mlKitInputRotation(CameraFrameRotation.cw270),
        InputImageRotation.rotation270deg,
      );
    });
  });

  group('mlKitDisplayRect', () {
    const imageSize = Size(200, 100);
    const detectedRect = Rect.fromLTRB(20, 10, 80, 50);

    test('normalizes an unrotated rectangle', () {
      expect(
        mlKitDisplayRect(
          detectedRect,
          imageSize: imageSize,
          rotation: InputImageRotation.rotation0deg,
          isIOS: false,
          mirrorHorizontally: false,
        ),
        const Rect.fromLTRB(0.1, 0.1, 0.4, 0.5),
      );
    });

    test('mirrors an unrotated rectangle horizontally', () {
      expect(
        mlKitDisplayRect(
          detectedRect,
          imageSize: imageSize,
          rotation: InputImageRotation.rotation0deg,
          isIOS: false,
          mirrorHorizontally: true,
        ),
        const Rect.fromLTRB(0.6, 0.1, 0.9, 0.5),
      );
    });

    test('uses Android dimensions for a clockwise rotation', () {
      expect(
        mlKitDisplayRect(
          detectedRect,
          imageSize: imageSize,
          rotation: InputImageRotation.rotation90deg,
          isIOS: false,
          mirrorHorizontally: false,
        ),
        const Rect.fromLTRB(0.2, 0.05, 0.8, 0.25),
      );
    });

    test('clamps coordinates to the normalized preview', () {
      expect(
        mlKitDisplayRect(
          const Rect.fromLTRB(-20, -10, 240, 120),
          imageSize: imageSize,
          rotation: InputImageRotation.rotation0deg,
          isIOS: false,
          mirrorHorizontally: false,
        ),
        const Rect.fromLTRB(0, 0, 1, 1),
      );
    });
  });
}
