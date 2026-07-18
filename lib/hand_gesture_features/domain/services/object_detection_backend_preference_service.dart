import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../enums/object_detection_backend.dart';

class ObjectDetectionBackendPreferenceService {
  const ObjectDetectionBackendPreferenceService();

  static const preferenceKey = 'object_detection_backend';

  static ObjectDetectionBackend platformDefault({
    required bool supportsNativeMethodChannel,
    required bool supportsOpenCvSdk,
    bool supportsUltralyticsYolo = true,
    bool supportsGoogleMlKit = true,
  }) {
    if (supportsNativeMethodChannel) {
      return ObjectDetectionBackend.nativeMethodChannel;
    }
    return supportsUltralyticsYolo
        ? ObjectDetectionBackend.ultralyticsYolo
        : ObjectDetectionBackend.objectDetectionPackage;
  }

  Future<ObjectDetectionBackend> load({
    required bool supportsNativeMethodChannel,
    required bool supportsOpenCvSdk,
    bool supportsUltralyticsYolo = true,
    bool supportsGoogleMlKit = true,
  }) async {
    final fallback = platformDefault(
      supportsNativeMethodChannel: supportsNativeMethodChannel,
      supportsOpenCvSdk: supportsOpenCvSdk,
      supportsUltralyticsYolo: supportsUltralyticsYolo,
      supportsGoogleMlKit: supportsGoogleMlKit,
    );

    try {
      final prefs = await SharedPreferences.getInstance();
      final savedName = prefs.getString(preferenceKey);

      // find the backend matching the saved name, if any
      ObjectDetectionBackend? saved;
      for (final backend in ObjectDetectionBackend.values) {
        if (backend.name == savedName) {
          saved = backend;
          break;
        }
      }

      if (saved == null) return fallback;

      final stillSupported = saved.isSupported(
        supportsNativeMethodChannel: supportsNativeMethodChannel,
        supportsOpenCvSdk: supportsOpenCvSdk,
        supportsUltralyticsYolo: supportsUltralyticsYolo,
        supportsGoogleMlKit: supportsGoogleMlKit,
      );

      return stillSupported ? saved : fallback;
    } catch (error, stackTrace) {
      debugPrint('Could not load object detector preference: $error');
      debugPrintStack(stackTrace: stackTrace);
      return fallback;
    }
  }

  Future<bool> save(
    ObjectDetectionBackend backend, {
    required bool supportsNativeMethodChannel,
    required bool supportsOpenCvSdk,
    bool supportsUltralyticsYolo = true,
    bool supportsGoogleMlKit = true,
  }) async {
    final supported = backend.isSupported(
      supportsNativeMethodChannel: supportsNativeMethodChannel,
      supportsOpenCvSdk: supportsOpenCvSdk,
      supportsUltralyticsYolo: supportsUltralyticsYolo,
      supportsGoogleMlKit: supportsGoogleMlKit,
    );
    if (!supported) return false;

    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.setString(preferenceKey, backend.name);
    } catch (error, stackTrace) {
      debugPrint('Could not save object detector preference: $error');
      debugPrintStack(stackTrace: stackTrace);
      return false;
    }
  }
}
