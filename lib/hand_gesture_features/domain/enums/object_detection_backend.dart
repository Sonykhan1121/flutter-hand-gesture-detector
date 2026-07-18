/// Object-detection implementation used by the camera screens.
enum ObjectDetectionBackend {
  /// The `object_detection` Flutter package with EfficientDet Lite.
  objectDetectionPackage,

  /// The `ultralytics_yolo` Flutter package.
  ultralyticsYolo,

  /// Google's native ML Kit object detector on Android and iOS.
  googleMlKit,

  /// The app-owned Android YOLO detector reached through a MethodChannel.
  nativeMethodChannel,

  /// OpenCV's Android Java SDK running the local YOLO model through DNN.
  opencvSdk,
}

/// The order used by the home-page detector picker.
const objectDetectionBackendOptions = <ObjectDetectionBackend>[
  ObjectDetectionBackend.objectDetectionPackage,
  ObjectDetectionBackend.ultralyticsYolo,
  ObjectDetectionBackend.googleMlKit,
  ObjectDetectionBackend.nativeMethodChannel,
  ObjectDetectionBackend.opencvSdk,
];

/// User-facing metadata for the available object-detection implementations.
extension ObjectDetectionBackendDetails on ObjectDetectionBackend {
  String get displayName => switch (this) {
    ObjectDetectionBackend.nativeMethodChannel => 'Native YOLO',
    ObjectDetectionBackend.opencvSdk => 'OpenCV SDK',
    ObjectDetectionBackend.ultralyticsYolo => 'Ultralytics YOLO',
    ObjectDetectionBackend.googleMlKit => 'Google ML Kit',
    ObjectDetectionBackend.objectDetectionPackage => 'EfficientDet Lite',
  };

  String get description => switch (this) {
    ObjectDetectionBackend.nativeMethodChannel =>
      'Android MethodChannel detector using the local YOLO model.',
    ObjectDetectionBackend.opencvSdk =>
      'Experimental Android OpenCV Java DNN detector.',
    ObjectDetectionBackend.ultralyticsYolo =>
      'Ultralytics on-device YOLO detector.',
    ObjectDetectionBackend.googleMlKit => 'Google on-device object detector.',
    ObjectDetectionBackend.objectDetectionPackage =>
      'EfficientDet Lite from the object_detection package.',
  };

  bool isSupported({
    required bool supportsNativeMethodChannel,
    required bool supportsOpenCvSdk,
    bool supportsUltralyticsYolo = true,
    bool supportsGoogleMlKit = true,
  }) {
    return switch (this) {
      ObjectDetectionBackend.nativeMethodChannel => supportsNativeMethodChannel,
      ObjectDetectionBackend.opencvSdk => supportsOpenCvSdk,
      ObjectDetectionBackend.ultralyticsYolo => supportsUltralyticsYolo,
      ObjectDetectionBackend.googleMlKit => supportsGoogleMlKit,
      _ => true,
    };
  }
}
