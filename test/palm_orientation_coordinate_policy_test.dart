import 'package:camera/camera.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gesture_detector/hand_gesture_features/presentation/utils/palm_orientation_coordinate_policy.dart';

void main() {
  group('palm orientation coordinate policy', () {
    test('normalizes chirality for every front camera', () {
      expect(
        shouldMirrorPalmOrientationCoordinates(CameraLensDirection.front),
        isTrue,
      );
    });

    test('does not mirror back or external camera chirality', () {
      expect(
        shouldMirrorPalmOrientationCoordinates(CameraLensDirection.back),
        isFalse,
      );
      expect(
        shouldMirrorPalmOrientationCoordinates(CameraLensDirection.external),
        isFalse,
      );
      expect(shouldMirrorPalmOrientationCoordinates(null), isFalse);
    });
  });
}
