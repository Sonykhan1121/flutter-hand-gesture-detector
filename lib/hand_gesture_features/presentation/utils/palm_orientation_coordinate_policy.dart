import 'package:camera/camera.dart';

/// Whether landmark chirality must be flipped before checking the palm side.
///
/// This is deliberately independent of preview/overlay mirroring. On iOS the
/// front-camera preview and landmark overlay already line up without an extra
/// display flip, but the detector's handedness result still uses the selfie
/// convention. The palm-facing geometry therefore needs a horizontal chirality
/// flip for every front camera on both iOS and Android.
bool shouldMirrorPalmOrientationCoordinates(
  CameraLensDirection? lensDirection,
) => lensDirection == CameraLensDirection.front;
