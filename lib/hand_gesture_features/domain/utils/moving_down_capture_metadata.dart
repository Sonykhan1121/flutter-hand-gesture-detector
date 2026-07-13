import 'package:camera/camera.dart';
import 'package:hand_detection/hand_detection.dart';

int movingDownInputOrientationDegrees(CameraFrameRotation? rotation) {
  return switch (rotation) {
    CameraFrameRotation.cw90 => 90,
    CameraFrameRotation.cw180 => 180,
    CameraFrameRotation.cw270 => 270,
    null => 0,
  };
}

String movingDownCameraFacing(CameraLensDirection direction) {
  return switch (direction) {
    CameraLensDirection.front => 'front',
    CameraLensDirection.back => 'back',
    CameraLensDirection.external => 'external',
  };
}

/// Detector handedness already represents the physical hand. Display mirroring
/// changes image/landmark X coordinates, not this label.
bool? movingDownPhysicalIsRight(Handedness? handedness) {
  return switch (handedness) {
    Handedness.right => true,
    Handedness.left => false,
    null => null,
  };
}
