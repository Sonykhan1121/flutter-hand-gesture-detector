/// Object-detection implementation used by the camera screens.
enum ObjectDetectionBackend {
  /// The `object_detection` Flutter package with EfficientDet Lite.
  objectDetectionPackage,

  /// The `ultralytics_yolo` Flutter package.
  ultralyticsYolo,

  /// Google's native ML Kit object detector on Android and iOS.
  googleMlKit,
}
