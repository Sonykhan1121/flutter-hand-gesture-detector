import 'package:flutter/material.dart';

import '../../domain/enums/object_detection_backend.dart';
import '../../domain/enums/stand_control_mode.dart';
import 'control_mode_card.dart';

/// Panel that lists the available stand-control modes on the home screen.
class SettingsPanel extends StatelessWidget {
  const SettingsPanel({
    super.key,
    required this.selectedMode,
    required this.disabledModes,
    required this.onSelectMode,
    required this.selectedObjectDetectionBackend,
    required this.onObjectDetectionBackendChanged,
    required this.supportsNativeMethodChannel,
    required this.supportsOpenCvSdk,
    required this.supportsUltralyticsYolo,
    required this.supportsGoogleMlKit,
    this.onMovingDownTrainingTap,
    this.showMovingDownTraining = true,
  });

  final StandControlMode selectedMode;
  final Set<StandControlMode> disabledModes;
  final ValueChanged<StandControlMode> onSelectMode;
  final ObjectDetectionBackend selectedObjectDetectionBackend;
  final ValueChanged<ObjectDetectionBackend> onObjectDetectionBackendChanged;
  final bool supportsNativeMethodChannel;
  final bool supportsOpenCvSdk;
  final bool supportsUltralyticsYolo;
  final bool supportsGoogleMlKit;
  final VoidCallback? onMovingDownTrainingTap;
  final bool showMovingDownTraining;

  Future<void> _showObjectDetectorPicker(BuildContext context) async {
    final selected = await showModalBottomSheet<ObjectDetectionBackend>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (sheetContext) {
        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Object Detector',
                style: TextStyle(
                  color: Color(0xFF101828),
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                'Choose the detector used the next time a camera opens.',
                style: TextStyle(
                  color: Color(0xFF667085),
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 14),
              RadioGroup<ObjectDetectionBackend>(
                groupValue: selectedObjectDetectionBackend,
                onChanged: (backend) {
                  if (backend != null &&
                      backend.isSupported(
                        supportsNativeMethodChannel:
                            supportsNativeMethodChannel,
                        supportsOpenCvSdk: supportsOpenCvSdk,
                        supportsUltralyticsYolo: supportsUltralyticsYolo,
                        supportsGoogleMlKit: supportsGoogleMlKit,
                      )) {
                    Navigator.pop(sheetContext, backend);
                  }
                },
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (final backend in objectDetectionBackendOptions)
                      _ObjectDetectorOption(
                        backend: backend,
                        isSupported: backend.isSupported(
                          supportsNativeMethodChannel:
                              supportsNativeMethodChannel,
                          supportsOpenCvSdk: supportsOpenCvSdk,
                          supportsUltralyticsYolo: supportsUltralyticsYolo,
                          supportsGoogleMlKit: supportsGoogleMlKit,
                        ),
                        onTap: () => Navigator.pop(sheetContext, backend),
                      ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );

    if (selected != null && context.mounted) {
      onObjectDetectionBackendChanged(selected);
    }
  }

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
            'Choose a control mode and object detector.',
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
                  key: const Key('handGestureControlCard'),
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
                const SizedBox(height: 14),
                ControlModeCard(
                  key: const Key('objectDetectorSettingsCard'),
                  isSelected: false,
                  isEnabled: true,
                  icon: Icons.memory_rounded,
                  title: 'Object Detector',
                  subtitle:
                      'Current: ${selectedObjectDetectionBackend.displayName}',
                  badgeText: 'DETECTOR',
                  accentColor: const Color(0xFFF79009),
                  onTap: () => _showObjectDetectorPicker(context),
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

class _ObjectDetectorOption extends StatelessWidget {
  const _ObjectDetectorOption({
    required this.backend,
    required this.isSupported,
    required this.onTap,
  });

  final ObjectDetectionBackend backend;
  final bool isSupported;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final unsupportedPlatform = switch (backend) {
      ObjectDetectionBackend.nativeMethodChannel ||
      ObjectDetectionBackend.opencvSdk => 'Android only.',
      ObjectDetectionBackend.ultralyticsYolo ||
      ObjectDetectionBackend.googleMlKit => 'Android and iOS only.',
      ObjectDetectionBackend.objectDetectionPackage => 'Unsupported.',
    };
    final subtitle = isSupported
        ? backend.description
        : '$unsupportedPlatform ${backend.description}';

    return ListTile(
      key: Key('objectDetectorOption_${backend.name}'),
      enabled: isSupported,
      contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      leading: Radio<ObjectDetectionBackend>(
        value: backend,
        enabled: isSupported,
      ),
      title: Text(
        backend.displayName,
        style: const TextStyle(fontWeight: FontWeight.w700),
      ),
      subtitle: Text(subtitle),
      onTap: isSupported ? onTap : null,
    );
  }
}
