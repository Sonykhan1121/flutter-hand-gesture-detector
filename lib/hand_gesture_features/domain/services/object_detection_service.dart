import 'dart:async';

import 'package:camera/camera.dart';
import 'package:object_detection/object_detection.dart' as od;

import '../enums/object_detection_backend.dart';
import '../models/app_object_detection.dart';

/// Common contract consumed by the camera and follow-target logic.
abstract interface class ObjectDetectionService {
  ObjectDetectionBackend get backend;

  bool get isBusy;

  Future<List<AppObjectDetection>> detect(
    CameraImage image, {
    od.CameraFrameRotation? rotation,
    CameraLensDirection? lensDirection,
  });

  Future<void> close();
}

/// Shared single-flight lifecycle; package-specific inference stays in each
/// concrete service.
abstract class SingleFlightObjectDetectionService
    implements ObjectDetectionService {
  var _isBusy = false;
  var _isClosed = false;
  Completer<void>? _activeDetectionFinished;

  @override
  bool get isBusy => _isBusy;

  bool get isClosed => _isClosed;

  @override
  Future<List<AppObjectDetection>> detect(
    CameraImage image, {
    od.CameraFrameRotation? rotation,
    CameraLensDirection? lensDirection,
  }) async {
    if (_isClosed) return const [];
    if (_isBusy) throw StateError('$runtimeType is busy.');

    final finished = Completer<void>();
    _activeDetectionFinished = finished;
    _isBusy = true;
    try {
      return await performDetection(
        image,
        rotation: rotation,
        lensDirection: lensDirection,
      );
    } finally {
      _isBusy = false;
      if (!finished.isCompleted) finished.complete();
      if (identical(_activeDetectionFinished, finished)) {
        _activeDetectionFinished = null;
      }
    }
  }

  Future<List<AppObjectDetection>> performDetection(
    CameraImage image, {
    od.CameraFrameRotation? rotation,
    CameraLensDirection? lensDirection,
  });

  Future<void> disposeBackend();

  @override
  Future<void> close() async {
    if (_isClosed) return;
    _isClosed = true;
    await _activeDetectionFinished?.future;
    await disposeBackend();
  }
}
