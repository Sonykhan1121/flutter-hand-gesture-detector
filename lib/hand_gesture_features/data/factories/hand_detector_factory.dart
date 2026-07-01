import 'package:flutter/foundation.dart';
import 'package:hand_detection/hand_detection.dart';

class HandDetectorFactory {
  const HandDetectorFactory._();

  static Future<HandDetector> create() {
    final useIosSafeInterpreter = defaultTargetPlatform == TargetPlatform.iOS;

    return HandDetector.create(
      mode: HandMode.boxesAndLandmarks,
      landmarkModel: HandLandmarkModel.full,
      detectorConf: 0.6,
      maxDetections: 1,
      minLandmarkScore: 0.5,
      performanceConfig: useIosSafeInterpreter
          ? const PerformanceConfig.xnnpack()
          : const PerformanceConfig(),
      useCompiledModel: !useIosSafeInterpreter,
      enableGestures: true,
    );
  }
}
