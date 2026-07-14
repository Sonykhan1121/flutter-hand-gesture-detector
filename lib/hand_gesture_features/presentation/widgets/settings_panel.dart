import 'package:flutter/material.dart';

import '../../domain/enums/stand_control_mode.dart';
import 'control_mode_card.dart';

/// Panel that lists the available stand-control modes on the home screen.
class SettingsPanel extends StatelessWidget {
  const SettingsPanel({
    super.key,
    required this.selectedMode,
    required this.disabledModes,
    required this.onSelectMode,
    this.onMovingDownTrainingTap,
    this.showMovingDownTraining = true,
  });

  final StandControlMode selectedMode;
  final Set<StandControlMode> disabledModes;
  final ValueChanged<StandControlMode> onSelectMode;
  final VoidCallback? onMovingDownTrainingTap;
  final bool showMovingDownTraining;

  @override
  /// Builds the settings title and the control-mode card list.
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
      decoration: const BoxDecoration(
        color: Color(0xFFF6F8FC),
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Control Settings',
            style: TextStyle(
              color: Color(0xFF101828),
              fontSize: 24,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Select one control mode for your mobile stand.',
            style: TextStyle(
              color: Color(0xFF667085),
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 20),
          Expanded(
            child: ListView(
              physics: const BouncingScrollPhysics(),
              children: [
                // ControlModeCard(
                //   isSelected: selectedMode == StandControlMode.automaticDetect,
                //   isEnabled: !disabledModes.contains(
                //     StandControlMode.automaticDetect,
                //   ),
                //   icon: Icons.person_search_rounded,
                //   title: 'Automatic Detect',
                //   subtitle: 'Person follow automatically',
                //   badgeText:
                //       disabledModes.contains(StandControlMode.automaticDetect)
                //       ? 'SOON'
                //       : 'AUTO',
                //   accentColor: const Color(0xFF12B76A),
                //   onTap: () => onSelectMode(StandControlMode.automaticDetect),
                // ),
                // const SizedBox(height: 14),
                ControlModeCard(
                  isSelected: selectedMode == StandControlMode.handGesture,
                  isEnabled: !disabledModes.contains(
                    StandControlMode.handGesture,
                  ),
                  icon: Icons.back_hand_rounded,
                  title: 'Hand Gesture',
                  subtitle: 'Control the stand using hand movement',
                  badgeText:
                      disabledModes.contains(StandControlMode.handGesture)
                      ? 'SOON'
                      : 'GESTURE',
                  accentColor: const Color(0xFF2E90FA),
                  onTap: () => onSelectMode(StandControlMode.handGesture),
                ),
                if (showMovingDownTraining) ...[
                  const SizedBox(height: 14),
                  ControlModeCard(
                    isSelected: false,
                    isEnabled: true,
                    icon: Icons.download_for_offline_rounded,
                    title: 'Record Moving Down',
                    subtitle: 'Capture two seconds of raw hand landmarks',
                    badgeText: 'TRAIN',
                    accentColor: const Color(0xFF12B76A),
                    onTap: onMovingDownTrainingTap ?? () {},
                  ),
                ],
                // const SizedBox(height: 14),
                // ControlModeCard(
                //   isSelected: selectedMode == StandControlMode.voiceCommand,
                //   isEnabled: !disabledModes.contains(
                //     StandControlMode.voiceCommand,
                //   ),
                //   icon: Icons.record_voice_over_rounded,
                //   title: 'Voice Command',
                //   subtitle: 'Give commands by voice',
                //   badgeText:
                //       disabledModes.contains(StandControlMode.voiceCommand)
                //       ? 'SOON'
                //       : 'VOICE',
                //   accentColor: const Color(0xFF9E77ED),
                //   onTap: () => onSelectMode(StandControlMode.voiceCommand),
                // ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
