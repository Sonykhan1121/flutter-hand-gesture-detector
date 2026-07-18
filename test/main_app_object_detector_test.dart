import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gesture_detector/hand_gesture_features/domain/enums/object_detection_backend.dart';
import 'package:gesture_detector/hand_gesture_features/domain/services/object_detection_backend_preference_service.dart';
import 'package:gesture_detector/main.dart';

class _FailingPreferenceService
    extends ObjectDetectionBackendPreferenceService {
  _FailingPreferenceService();

  @override
  Future<bool> save(
    ObjectDetectionBackend backend, {
    required bool supportsNativeMethodChannel,
    required bool supportsOpenCvSdk,
    bool supportsUltralyticsYolo = true,
    bool supportsGoogleMlKit = true,
  }) async {
    return false;
  }
}

void main() {
  testWidgets('failed persistence keeps the session choice and warns', (
    tester,
  ) async {
    await tester.pumpWidget(
      GestureDetectorApp(
        showFloatingCameraDetectionButton: false,
        showMovingDownTrainingListItem: false,
        initialObjectDetectionBackend: ObjectDetectionBackend.ultralyticsYolo,
        supportsNativeMethodChannel: true,
        supportsOpenCvSdk: true,
        objectDetectionBackendPreferenceService: _FailingPreferenceService(),
      ),
    );

    final settingsCard = find.byKey(const Key('objectDetectorSettingsCard'));
    await tester.ensureVisible(settingsCard);
    await tester.tap(settingsCard);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Google ML Kit'));
    await tester.pumpAndSettle();

    expect(find.text('Current: Google ML Kit'), findsOneWidget);
    expect(
      find.text(
        'Detector changed for this session, but it could not be saved.',
      ),
      findsOneWidget,
    );
  });
}
