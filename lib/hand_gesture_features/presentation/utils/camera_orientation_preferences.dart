import 'package:flutter/services.dart';

import '../../domain/enums/camera_preview_mode.dart';

/// Orientations supported by the camera pages on both Android and iOS.
const supportedCameraDeviceOrientations = <DeviceOrientation>[
  DeviceOrientation.portraitUp,
  DeviceOrientation.landscapeLeft,
  DeviceOrientation.landscapeRight,
];

/// Capture orientation used for videos while the Flutter UI stays portrait.
DeviceOrientation recordingCameraDeviceOrientation(CameraPreviewMode mode) =>
    mode.isLandscape
        ? DeviceOrientation.landscapeLeft
        : DeviceOrientation.portraitUp;
