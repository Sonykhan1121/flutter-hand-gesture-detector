import 'package:flutter/material.dart';
import 'package:gesture_detector/utils/app_snack_bar.dart';

import 'hand_gesture_features/domain/enums/object_detection_backend.dart';
import 'hand_gesture_features/domain/enums/stand_control_mode.dart';
import 'hand_gesture_features/presentation/screens/admin_hand_gesture_live_screen.dart';
import 'hand_gesture_features/presentation/screens/face_object_debug_camera_screen.dart';
import 'hand_gesture_features/presentation/screens/moving_down_capture_screen.dart';
import 'hand_gesture_features/stand_control_home_page.dart';

void main() {
  // App feature handlers: change only these three values when needed.
  const showFloatingCameraDetectionButton = true;
  const showMovingDownTrainingListItem = false;
  const objectDetectionBackend = ObjectDetectionBackend.ultralyticsYolo;

  runApp(
    const MyApp(
      showFloatingCameraDetectionButton: showFloatingCameraDetectionButton,
      showMovingDownTrainingListItem: showMovingDownTrainingListItem,
      objectDetectionBackend: objectDetectionBackend,
    ),
  );
}

/// Root widget that configures app theme and opens the stand-control flow.
class MyApp extends StatelessWidget {
  const MyApp({
    super.key,
    this.showFloatingCameraDetectionButton = true,
    this.showMovingDownTrainingListItem = true,
    this.objectDetectionBackend = ObjectDetectionBackend.ultralyticsYolo,
  });

  final bool showFloatingCameraDetectionButton;
  final bool showMovingDownTrainingListItem;
  final ObjectDetectionBackend objectDetectionBackend;

  @override
  /// Builds the Material app and wires home-screen actions to navigation.
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Smart Stand Control',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF2E90FA)),
        useMaterial3: true,
      ),
      home: Builder(
        builder: (context) {
          return StandControlHomePage(
            initialMode: StandControlMode.handGesture,
            showDebugCameraButton: showFloatingCameraDetectionButton,
            showMovingDownTraining: showMovingDownTrainingListItem,
            onModeChanged: (mode) {
              debugPrint('New mode : $mode');
            },
            onDebugCameraTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => FaceObjectDebugCameraScreen(
                    objectDetectionBackend: objectDetectionBackend,
                  ),
                ),
              );
            },
            onAutomaticDetectTap: () {
              AppSnackBar.show(
                context: context,
                message: 'Automatic Detect is coming soon.',
              );
            },
            onHandGestureTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => AdminHandGestureLiveScreen(
                    fontorback: 1,
                    objectDetectionBackend: objectDetectionBackend,
                  ),
                ),
              );
            },
            onMovingDownTrainingTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const MovingDownCaptureScreen(),
                ),
              );
            },
            onVoiceCommandTap: () {
              AppSnackBar.show(
                context: context,
                message: 'Voice Command is coming soon.',
              );
            },
          );
        },
      ),
    );
  }
}
