import 'package:flutter/material.dart';
import 'package:gesture_detector/utils/app_snack_bar.dart';

import 'hand_gesture_features/domain/enums/stand_control_mode.dart';
import 'hand_gesture_features/presentation/screens/admin_hand_gesture_live_screen.dart';
import 'hand_gesture_features/presentation/screens/face_object_debug_camera_screen.dart';
import 'hand_gesture_features/stand_control_home_page.dart';

/// Starts the Flutter application.
void main() {
  runApp(const MyApp());
}

/// Root widget that configures app theme and opens the stand-control flow.
class MyApp extends StatelessWidget {
  const MyApp({super.key});

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
            onModeChanged: (mode) {
              debugPrint('New mode : $mode');
            },
            onDebugCameraTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const FaceObjectDebugCameraScreen(),
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
                  builder: (_) =>
                      const AdminHandGestureLiveScreen(fontorback: 1),
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
