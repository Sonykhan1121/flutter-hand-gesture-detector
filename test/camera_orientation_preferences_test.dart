import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gesture_detector/hand_gesture_features/domain/enums/camera_preview_mode.dart';
import 'package:gesture_detector/hand_gesture_features/presentation/utils/camera_orientation_preferences.dart';

void main() {
  test('camera pages support portrait and both landscape directions', () {
    expect(supportedCameraDeviceOrientations, const <DeviceOrientation>[
      DeviceOrientation.portraitUp,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
  });

  test('uses the selected preview mode for recording capture only', () {
    expect(
      recordingCameraDeviceOrientation(CameraPreviewMode.portrait),
      DeviceOrientation.portraitUp,
    );
    expect(
      recordingCameraDeviceOrientation(CameraPreviewMode.landscape),
      DeviceOrientation.landscapeLeft,
    );
  });

  test('camera-only transition lasts 450 milliseconds', () {
    expect(cameraPreviewRotationDuration, const Duration(milliseconds: 450));
  });
}
