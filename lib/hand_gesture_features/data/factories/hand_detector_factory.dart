import 'package:flutter/foundation.dart';
import 'package:hand_detection/hand_detection.dart';

class HandDetectorFactory {
  const HandDetectorFactory._();

  static Future<HandDetector> create() async {
    final useIosSafeInterpreter = defaultTargetPlatform == TargetPlatform.iOS;
    if (useIosSafeInterpreter) {
      return _createDetector(useCompiledModel: false);
    }

    try {
      return await _createDetector(useCompiledModel: true);
    } catch (error) {
      debugPrint(
        'Compiled hand detector init failed; falling back to XNNPACK: $error',
      );
      return _createDetector(useCompiledModel: false);
    }
  }

  static Future<HandDetector> _createDetector({
    required bool useCompiledModel,
  }) {
    return HandDetector.create(
      mode: HandMode.boxesAndLandmarks,
      landmarkModel: HandLandmarkModel.full,
      detectorConf: 0.60,
      maxDetections: 1,
      minLandmarkScore: 0.6,
      performanceConfig: const PerformanceConfig.xnnpack(),
      useCompiledModel: useCompiledModel,
      enableTracking: true,
      trackingConfig: const TrackingConfig(),
      enableGestures: true,
    );
  }
}
