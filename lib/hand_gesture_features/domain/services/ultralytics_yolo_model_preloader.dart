import 'package:flutter/foundation.dart';
import 'package:ultralytics_yolo/ultralytics_yolo.dart';

import '../constants/hand_gesture_thresholds.dart';

typedef YoloModelInspector =
    Future<Map<String, dynamic>> Function(String modelPath);

/// Downloads and inspects the official YOLO model without loading inference.
///
/// Calls share one in-flight future, so app-start prefetch and camera startup
/// can never launch duplicate downloads. Failed attempts are not cached and
/// can be retried when the camera is opened later.
class UltralyticsYoloModelPreloader {
  UltralyticsYoloModelPreloader({YoloModelInspector? inspectModel})
    : _inspectModel = inspectModel ?? YOLO.inspectModel;

  final YoloModelInspector _inspectModel;

  Future<Map<String, dynamic>>? _inFlight;
  Map<String, dynamic>? _metadata;

  bool get isPrepared => _metadata != null;
  bool get isPreparing => _inFlight != null;

  Future<Map<String, dynamic>> prepare() {
    final metadata = _metadata;
    if (metadata != null) return Future.value(metadata);

    final inFlight = _inFlight;
    if (inFlight != null) return inFlight;

    final operation = _prepareOnce();
    _inFlight = operation;
    return operation;
  }

  /// Starts preparation without allowing a network failure to escape.
  Future<void> prefetch() async {
    try {
      await prepare();
      debugPrint('Ultralytics YOLO model is ready in the local cache.');
    } catch (error, stackTrace) {
      debugPrint('Ultralytics YOLO background download deferred: $error');
      debugPrintStack(stackTrace: stackTrace);
    }
  }

  Future<Map<String, dynamic>> _prepareOnce() async {
    try {
      final metadata = Map<String, dynamic>.unmodifiable(
        await Future.sync(
          () => _inspectModel(HandGestureThresholds.ultralyticsYoloModelId),
        ),
      );
      _metadata = metadata;
      return metadata;
    } finally {
      _inFlight = null;
    }
  }
}

final ultralyticsYoloModelPreloader = UltralyticsYoloModelPreloader();
