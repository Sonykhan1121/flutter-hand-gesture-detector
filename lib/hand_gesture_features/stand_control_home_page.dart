import 'package:flutter/material.dart';
import 'package:gesture_detector/hand_gesture_features/presentation/widgets/settings_panel.dart';
import 'package:gesture_detector/hand_gesture_features/presentation/widgets/stand_hero_section.dart';

import 'domain/enums/stand_control_mode.dart';

/// Home page where the user chooses how the smart stand will be controlled.
class StandControlHomePage extends StatefulWidget {
  final StandControlMode initialMode;
  final Set<StandControlMode> disabledModes;
  final ValueChanged<StandControlMode>? onModeChanged;
  final VoidCallback? onAutomaticDetectTap;
  final VoidCallback? onHandGestureTap;
  final VoidCallback? onVoiceCommandTap;
  final VoidCallback? onDebugCameraTap;

  const StandControlHomePage({
    super.key,
    this.initialMode = StandControlMode.handGesture,
    this.disabledModes = const {},
    this.onModeChanged,
    this.onAutomaticDetectTap,
    this.onHandGestureTap,
    this.onVoiceCommandTap,
    this.onDebugCameraTap,
  });

  @override
  /// Creates state that remembers the currently selected control mode.
  State<StandControlHomePage> createState() => _StandControlHomePageState();
}

/// Holds the selected mode and dispatches tap callbacks for each mode.
class _StandControlHomePageState extends State<StandControlHomePage> {
  late StandControlMode _selectedMode;

  @override
  /// Copies the starting mode from the widget into mutable screen state.
  void initState() {
    super.initState();
    _selectedMode = widget.initialMode;
  }

  /// Updates the selected mode unless it is disabled, then runs its callback.
  void _selectMode(StandControlMode mode) {
    if (widget.disabledModes.contains(mode)) {
      _notifyModeTap(mode);
      return;
    }

    setState(() {
      _selectedMode = mode;
    });

    widget.onModeChanged?.call(mode);
    _notifyModeTap(mode);
  }

  /// Calls the mode-specific handler provided by the app root.
  void _notifyModeTap(StandControlMode mode) {
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
  /// Builds the hero artwork and the mode settings panel.
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);

    return Scaffold(
      backgroundColor: const Color(0xFFF6F8FC),
      floatingActionButton: FloatingActionButton(
        key: const Key('faceObjectDebugCameraButton'),
        heroTag: 'faceObjectDebugCameraButton',
        tooltip: 'Face/Object Debug',
        onPressed: widget.onDebugCameraTap,
        child: const Icon(Icons.center_focus_strong),
      ),
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
                disabledModes: widget.disabledModes,
                onSelectMode: _selectMode,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
