import 'package:hand_detection/hand_detection.dart';

class HandDetectorFactory {
  const HandDetectorFactory._();

  static Future<HandDetector> create() {
    return HandDetector.create(
      mode: HandMode.boxesAndLandmarks,
      landmarkModel: HandLandmarkModel.full,
      detectorConf: 0.6,
      maxDetections: 2,
      minLandmarkScore: 0.5,
      performanceConfig: const PerformanceConfig.xnnpack(),
      enableGestures: true,
      gestureMinConfidence: 0.5,
    );
  }
}
