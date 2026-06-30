import 'package:flutter/material.dart';
import 'package:gesture_detector/hand_gesture_features/presentation/painters/mobile_stand_painter.dart';
import 'package:gesture_detector/hand_gesture_features/presentation/widgets/control_mode_card.dart';
import 'package:gesture_detector/hand_gesture_features/presentation/widgets/settings_panel.dart';
import 'package:gesture_detector/hand_gesture_features/presentation/widgets/stand_hero_section.dart';

import 'domain/enums/stand_control_mode.dart';

class StandControlHomePage extends StatefulWidget {

  final StandControlMode initialMode;
  final ValueChanged<StandControlMode>? onModeChanged;
  final VoidCallback? onAutomaticDetectTap;
  final VoidCallback? onHandGestureTap;
  final VoidCallback? onVoiceCommandTap;

  const StandControlHomePage({
    super.key,
    this.initialMode = StandControlMode.handGesture,
    this.onModeChanged,
    this.onAutomaticDetectTap,
    this.onHandGestureTap,
    this.onVoiceCommandTap,
  });



  @override
  State<StandControlHomePage> createState() => _StandControlHomePageState();
}

class _StandControlHomePageState extends State<StandControlHomePage> {
  late StandControlMode _selectedMode;

  @override
  void initState() {
    super.initState();
    _selectedMode = widget.initialMode;
  }

  void _selectMode(StandControlMode mode) {
    setState(() {
      _selectedMode = mode;
    });

    widget.onModeChanged?.call(mode);

    switch (mode) {
      case StandControlMode.automaticDetect:
        widget.onAutomaticDetectTap?.call();
        break;
      case StandControlMode.handGesture:
        widget.onHandGestureTap?.call();
        break;
      case StandControlMode.voiceCommand:
        widget.onVoiceCommandTap?.call();
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);

    return Scaffold(
      backgroundColor: const Color(0xFFF6F8FC),
      body: SafeArea(
        child: Column(
          children: [
            SizedBox(
              height: size.height * 0.30,
              width: double.infinity,
              child: const StandHeroSection(),
            ),
            Expanded(
              child: SettingsPanel(
                selectedMode: _selectedMode,
                onSelectMode: _selectMode,
              ),
            ),
          ],
        ),
      ),
    );
  }
}








