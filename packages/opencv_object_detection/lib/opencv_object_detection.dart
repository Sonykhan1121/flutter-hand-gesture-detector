import 'package:flutter/services.dart';

/// Thin Dart API for the app-owned Android OpenCV DNN detector.
class OpenCvObjectDetection {
  const OpenCvObjectDetection({
    MethodChannel channel = const MethodChannel(channelName),
  }) : _channel = channel;

  static const channelName = 'smart_stand/opencv_object_detection';

  final MethodChannel _channel;

  Future<Map<Object?, Object?>> initialize({
    required String modelAsset,
    required String metadataAsset,
    required double confidenceThreshold,
    required double iouThreshold,
    required int maxResults,
    required int expectedClassCount,
  }) async {
    return await _channel.invokeMapMethod<Object?, Object?>('initialize', {
          'modelAsset': modelAsset,
          'metadataAsset': metadataAsset,
          'confidenceThreshold': confidenceThreshold,
          'iouThreshold': iouThreshold,
          'maxResults': maxResults,
          'expectedClassCount': expectedClassCount,
        }) ??
        const {};
  }

  Future<Map<Object?, Object?>> detect(Map<String, Object?> frame) async {
    return await _channel.invokeMapMethod<Object?, Object?>('detect', frame) ??
        const {};
  }

  Future<Map<Object?, Object?>> getCapabilities() async {
    return await _channel.invokeMapMethod<Object?, Object?>(
          'getCapabilities',
        ) ??
        const {};
  }

  Future<void> dispose() => _channel.invokeMethod<void>('dispose');
}
