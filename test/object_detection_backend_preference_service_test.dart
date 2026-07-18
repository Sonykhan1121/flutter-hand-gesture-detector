import 'package:flutter_test/flutter_test.dart';
import 'package:gesture_detector/hand_gesture_features/domain/enums/object_detection_backend.dart';
import 'package:gesture_detector/hand_gesture_features/domain/services/object_detection_backend_preference_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('uses the platform default when no preference exists', () async {
    final service = ObjectDetectionBackendPreferenceService();

    expect(
      await service.load(
        supportsNativeMethodChannel: true,
        supportsOpenCvSdk: true,
      ),
      ObjectDetectionBackend.nativeMethodChannel,
    );
    expect(
      await service.load(
        supportsNativeMethodChannel: false,
        supportsOpenCvSdk: false,
      ),
      ObjectDetectionBackend.ultralyticsYolo,
    );
  });

  test('saved selection is restored by a new service instance', () async {
    final writer = ObjectDetectionBackendPreferenceService();

    expect(
      await writer.save(
        ObjectDetectionBackend.googleMlKit,
        supportsNativeMethodChannel: true,
        supportsOpenCvSdk: true,
      ),
      isTrue,
    );

    final reader = ObjectDetectionBackendPreferenceService();
    expect(
      await reader.load(
        supportsNativeMethodChannel: true,
        supportsOpenCvSdk: true,
      ),
      ObjectDetectionBackend.googleMlKit,
    );
  });

  test('invalid stored enum name falls back to the platform default', () async {
    SharedPreferences.setMockInitialValues({
      ObjectDetectionBackendPreferenceService.preferenceKey: 'removedBackend',
    });

    final service = ObjectDetectionBackendPreferenceService();

    expect(
      await service.load(
        supportsNativeMethodChannel: true,
        supportsOpenCvSdk: true,
      ),
      ObjectDetectionBackend.nativeMethodChannel,
    );
  });

  test('unsupported stored Native YOLO falls back on iOS', () async {
    SharedPreferences.setMockInitialValues({
      ObjectDetectionBackendPreferenceService.preferenceKey:
          ObjectDetectionBackend.nativeMethodChannel.name,
    });
    final service = ObjectDetectionBackendPreferenceService();

    expect(
      await service.load(
        supportsNativeMethodChannel: false,
        supportsOpenCvSdk: false,
      ),
      ObjectDetectionBackend.ultralyticsYolo,
    );
    expect(
      await service.save(
        ObjectDetectionBackend.nativeMethodChannel,
        supportsNativeMethodChannel: false,
        supportsOpenCvSdk: false,
      ),
      isFalse,
    );
  });

  test('unsupported stored OpenCV SDK falls back on iOS', () async {
    SharedPreferences.setMockInitialValues({
      ObjectDetectionBackendPreferenceService.preferenceKey:
          ObjectDetectionBackend.opencvSdk.name,
    });
    final service = ObjectDetectionBackendPreferenceService();

    expect(
      await service.load(
        supportsNativeMethodChannel: false,
        supportsOpenCvSdk: false,
      ),
      ObjectDetectionBackend.ultralyticsYolo,
    );
    expect(
      await service.save(
        ObjectDetectionBackend.opencvSdk,
        supportsNativeMethodChannel: false,
        supportsOpenCvSdk: false,
      ),
      isFalse,
    );
  });

  test('Ultralytics is unavailable outside Android and iOS', () async {
    final service = ObjectDetectionBackendPreferenceService();

    expect(
      ObjectDetectionBackend.ultralyticsYolo.isSupported(
        supportsNativeMethodChannel: false,
        supportsOpenCvSdk: false,
        supportsUltralyticsYolo: false,
      ),
      isFalse,
    );
    expect(
      await service.load(
        supportsNativeMethodChannel: false,
        supportsOpenCvSdk: false,
        supportsUltralyticsYolo: false,
      ),
      ObjectDetectionBackend.objectDetectionPackage,
    );
    expect(
      await service.save(
        ObjectDetectionBackend.ultralyticsYolo,
        supportsNativeMethodChannel: false,
        supportsOpenCvSdk: false,
        supportsUltralyticsYolo: false,
      ),
      isFalse,
    );
  });

  test('Google ML Kit is unavailable outside Android and iOS', () async {
    SharedPreferences.setMockInitialValues({
      ObjectDetectionBackendPreferenceService.preferenceKey:
          ObjectDetectionBackend.googleMlKit.name,
    });
    final service = ObjectDetectionBackendPreferenceService();

    expect(
      ObjectDetectionBackend.googleMlKit.isSupported(
        supportsNativeMethodChannel: false,
        supportsOpenCvSdk: false,
        supportsGoogleMlKit: false,
      ),
      isFalse,
    );
    expect(
      await service.load(
        supportsNativeMethodChannel: false,
        supportsOpenCvSdk: false,
        supportsGoogleMlKit: false,
      ),
      ObjectDetectionBackend.ultralyticsYolo,
    );
    expect(
      await service.save(
        ObjectDetectionBackend.googleMlKit,
        supportsNativeMethodChannel: false,
        supportsOpenCvSdk: false,
        supportsGoogleMlKit: false,
      ),
      isFalse,
    );
  });
}
