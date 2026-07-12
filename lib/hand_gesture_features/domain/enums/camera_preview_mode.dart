/// Visual orientation of the camera layer inside the fixed portrait UI.
enum CameraPreviewMode {
  portrait,
  landscape;

  bool get isLandscape => this == CameraPreviewMode.landscape;
}

/// Duration of the camera-only 9:16 ↔ 16:9 transition.
const cameraPreviewRotationDuration = Duration(milliseconds: 450);
