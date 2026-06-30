import 'package:flutter/material.dart';
import 'package:gesture_detector/utils/app_snack_bar.dart';

import 'hand_gesture_features/domain/enums/stand_control_mode.dart';
import 'hand_gesture_features/presentation/screens/admin_hand_gesture_live_screen.dart';
import 'hand_gesture_features/stand_control_home_page.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
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
            onModeChanged: (mode)
            {
              debugPrint('New mode : $mode');
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
