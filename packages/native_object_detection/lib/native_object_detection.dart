import 'package:flutter/services.dart';

/// Thin Dart API for the app-owned Android object detector.
class NativeObjectDetection {
  const NativeObjectDetection({
    MethodChannel channel = const MethodChannel(channelName),
  }) : _channel = channel;

  static const channelName = 'smart_stand/native_object_detection';

  final MethodChannel _channel;

  Future<Map<Object?, Object?>> initialize({
    required String modelAsset,
    required double confidenceThreshold,
    required double iouThreshold,
    required int maxResults,
    required int expectedClassCount,
    required bool useGpu,
  }) async {
    return await _channel.invokeMapMethod<Object?, Object?>('initialize', {
          'modelAsset': modelAsset,
          'confidenceThreshold': confidenceThreshold,
          'iouThreshold': iouThreshold,
          'maxResults': maxResults,
          'expectedClassCount': expectedClassCount,
          'useGpu': useGpu,
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
