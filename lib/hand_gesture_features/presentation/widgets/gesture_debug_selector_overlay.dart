import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../domain/enums/gesture_debug_mode.dart';
import '../../domain/utils/camera_preview_geometry.dart';

/// Camera-card overlay selected by holding landmark point 8 over one tile.
class GestureDebugSelectorOverlay extends StatefulWidget {
  const GestureDebugSelectorOverlay({
    super.key,
    required this.selectedMode,
    required this.indexTip,
    required this.detectionImageSize,
    required this.mirrorHorizontally,
    required this.previewQuarterTurns,
    required this.useRecordingPreviewMapping,
    required this.onModeSelected,
    required this.onCancel,
    required this.onExitDetection,
    this.selectionHoldDuration = const Duration(seconds: 2),
  });

  final GestureDebugMode selectedMode;
  final Offset? indexTip;
  final Size detectionImageSize;
  final bool mirrorHorizontally;
  final int previewQuarterTurns;
  final bool useRecordingPreviewMapping;
  final ValueChanged<GestureDebugMode> onModeSelected;
  final VoidCallback onCancel;
  final VoidCallback onExitDetection;
  final Duration selectionHoldDuration;

  @override
  State<GestureDebugSelectorOverlay> createState() =>
      _GestureDebugSelectorOverlayState();
}

class _GestureDebugSelectorOverlayState
    extends State<GestureDebugSelectorOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _holdController;
  Timer? _selectionTimer;
  _DebugTileChoice? _hoveredChoice;
  _DebugTileChoice? _scheduledChoice;
  bool _selectionCommitted = false;
  bool _hoverUpdateScheduled = false;

  static const _choices = <_DebugTileChoice>[
    _DebugTileChoice(
      mode: GestureDebugMode.direction,
      label: 'Directions',
      icon: Icons.open_with,
    ),
    _DebugTileChoice(
      mode: GestureDebugMode.punch,
      label: 'Punch',
      icon: Icons.sports_mma,
    ),
    _DebugTileChoice(
      mode: GestureDebugMode.zoomIn,
      label: 'Zoom In',
      icon: Icons.zoom_in,
    ),
    _DebugTileChoice(
      mode: GestureDebugMode.zoomOut,
      label: 'Zoom Out',
      icon: Icons.zoom_out,
    ),
    _DebugTileChoice(
      mode: GestureDebugMode.returnMain,
      label: 'Return Main',
      icon: Icons.home_outlined,
    ),
    _DebugTileChoice(
      mode: GestureDebugMode.recording,
      label: 'Recording',
      icon: Icons.videocam_outlined,
    ),
    _DebugTileChoice(
      mode: GestureDebugMode.callMe,
      label: 'Call Me',
      icon: Icons.call_outlined,
    ),
    _DebugTileChoice(
      mode: GestureDebugMode.followObject,
      label: 'Follow Object',
      icon: Icons.center_focus_strong,
    ),
    _DebugTileChoice(
      mode: GestureDebugMode.off,
      label: 'Debug Off',
      icon: Icons.visibility_off_outlined,
    ),
    _DebugTileChoice.cancel(label: 'Cancel', icon: Icons.close),
    _DebugTileChoice.exit(label: 'Exit Detection', icon: Icons.exit_to_app),
  ];

  @override
  void initState() {
    super.initState();
    _holdController = AnimationController(
      vsync: this,
      duration: widget.selectionHoldDuration,
    );
  }

  @override
  void didUpdateWidget(covariant GestureDebugSelectorOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectionHoldDuration != widget.selectionHoldDuration) {
      _holdController.duration = widget.selectionHoldDuration;
      final choice = _hoveredChoice;
      if (choice != null && !_selectionCommitted) {
        _restartHold(choice);
      }
    }
  }

  @override
  void dispose() {
    _selectionTimer?.cancel();
    _holdController.dispose();
    super.dispose();
  }

  void _commitChoice(_DebugTileChoice choice) {
    if (!mounted || _selectionCommitted || _hoveredChoice != choice) return;
    _selectionCommitted = true;
    _selectionTimer?.cancel();
    if (choice.isCancel) {
      widget.onCancel();
    } else if (choice.isExit) {
      widget.onExitDetection();
    } else {
      widget.onModeSelected(choice.mode!);
    }
  }

  void _restartHold(_DebugTileChoice choice) {
    _selectionTimer?.cancel();
    _holdController
      ..stop()
      ..value = 0
      ..forward();
    _selectionTimer = Timer(
      widget.selectionHoldDuration,
      () => _commitChoice(choice),
    );
  }

  void _scheduleHoveredChoice(_DebugTileChoice? choice) {
    _scheduledChoice = choice;
    if (_hoverUpdateScheduled) return;
    _hoverUpdateScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _hoverUpdateScheduled = false;
      if (!mounted || _selectionCommitted) return;
      final nextChoice = _scheduledChoice;
      if (nextChoice == _hoveredChoice) return;
      setState(() {
        _hoveredChoice = nextChoice;
        _selectionTimer?.cancel();
        _holdController.stop();
        _holdController.value = 0;
        if (nextChoice != null) {
          _restartHold(nextChoice);
        }
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    return AbsorbPointer(
      child: ColoredBox(
        key: const Key('gestureDebugSelectorBackdrop'),
        color: Colors.transparent,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final canvasSize = constraints.biggest;
            final compactLayout = canvasSize.height < 400;
            final sourceTip = widget.indexTip;
            final cursor = sourceTip == null
                ? null
                : detectionPointToPreviewCanvas(
                    sourcePoint: sourceTip,
                    detectionImageSize: widget.detectionImageSize,
                    canvasSize: canvasSize,
                    mirrorHorizontally: widget.mirrorHorizontally,
                    previewQuarterTurns: widget.previewQuarterTurns,
                    useRecordingPreviewMapping:
                        widget.useRecordingPreviewMapping,
                  );
            final tileRects = _tileRects(
              canvasSize,
              compactLayout: compactLayout,
            );
            _DebugTileChoice? hoveredChoice;
            if (cursor != null && cursor.dx.isFinite && cursor.dy.isFinite) {
              for (var index = 0; index < _choices.length; index += 1) {
                if (tileRects[index].contains(cursor)) {
                  hoveredChoice = _choices[index];
                  break;
                }
              }
            }
            _scheduleHoveredChoice(hoveredChoice);

            return Stack(
              key: const Key('gestureDebugSelectorGrid'),
              children: [
                Positioned(
                  left: compactLayout ? 8 : 12,
                  right: compactLayout ? 8 : 12,
                  top: compactLayout ? 3 : 10,
                  height: compactLayout ? 38 : 48,
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: SizedBox(
                      width: math.max(1, canvasSize.width - 24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Text(
                            'Choose debug drawing',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          Text(
                            cursor == null
                                ? 'Show point 8, then hold inside a box for 2 seconds'
                                : 'Hold point 8 inside one box for 2 seconds',
                            textAlign: TextAlign.center,
                            maxLines: 2,
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                for (var index = 0; index < _choices.length; index += 1)
                  _buildTile(
                    choice: _choices[index],
                    rect: tileRects[index],
                    compactLayout: compactLayout,
                  ),
                if (cursor != null && cursor.dx.isFinite && cursor.dy.isFinite)
                  Positioned(
                    key: const Key('gestureDebugPoint8Cursor'),
                    left: cursor.dx - 10,
                    top: cursor.dy - 10,
                    width: 20,
                    height: 20,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFD740),
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.black, width: 3),
                        boxShadow: const [
                          BoxShadow(color: Colors.white, blurRadius: 5),
                        ],
                      ),
                      child: const Center(
                        child: Text(
                          '8',
                          style: TextStyle(
                            color: Colors.black,
                            fontSize: 8,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }

  Positioned _buildTile({
    required _DebugTileChoice choice,
    required Rect rect,
    required bool compactLayout,
  }) {
    final isHovered = choice == _hoveredChoice;
    final isSelected =
        choice.mode != null && choice.mode == widget.selectedMode;
    final borderColor = isHovered
        ? const Color(0xFFFFD740)
        : isSelected
        ? const Color(0xFF69F0AE)
        : choice.isExit
        ? const Color(0xFFFF5252)
        : Colors.white38;

    return Positioned.fromRect(
      rect: rect,
      child: AnimatedBuilder(
        animation: _holdController,
        builder: (context, _) {
          final progress = isHovered ? _holdController.value : 0.0;
          final totalSeconds =
              widget.selectionHoldDuration.inMilliseconds / 1000;
          final elapsedSeconds = progress * totalSeconds;
          return Container(
            key: Key(
              choice.isCancel
                  ? 'gestureDebugTile_cancel'
                  : choice.isExit
                  ? 'gestureDebugTile_exitDetection'
                  : 'gestureDebugTile_${choice.mode!.name}',
            ),
            decoration: BoxDecoration(
              color: isHovered
                  ? const Color(0x663D3510)
                  : isSelected
                  ? const Color(0x66123827)
                  : choice.isExit
                  ? const Color(0x663D1010)
                  : const Color(0x55202020),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: borderColor, width: 2),
            ),
            child: Stack(
              fit: StackFit.expand,
              children: [
                Align(
                  alignment: Alignment.bottomCenter,
                  child: FractionallySizedBox(
                    widthFactor: progress,
                    child: Container(
                      height: 5,
                      decoration: const BoxDecoration(
                        color: Color(0xFFFFD740),
                        borderRadius: BorderRadius.vertical(
                          bottom: Radius.circular(10),
                        ),
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: EdgeInsets.symmetric(
                    horizontal: compactLayout ? 3 : 6,
                    vertical: 2,
                  ),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: SizedBox(
                      width: math.max(40, rect.width - 12),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(choice.icon, color: borderColor, size: 30),
                          const SizedBox(height: 4),
                          Text(
                            choice.label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          if (isHovered)
                            Text(
                              '${elapsedSeconds.toStringAsFixed(1)}s / '
                              '${totalSeconds.toStringAsFixed(1)}s',
                              style: const TextStyle(
                                color: Color(0xFFFFD740),
                                fontSize: 11,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  List<Rect> _tileRects(Size size, {required bool compactLayout}) {
    final horizontalPadding = compactLayout ? 8.0 : 12.0;
    final top = compactLayout ? 44.0 : 64.0;
    final bottomPadding = compactLayout ? 8.0 : 12.0;
    final columnGap = compactLayout ? 7.0 : 9.0;
    final rowGap = compactLayout ? 4.0 : 7.0;
    final tileWidth = (size.width - horizontalPadding * 2 - columnGap) / 2;
    final tileHeight = (size.height - top - bottomPadding - rowGap * 5) / 6;

    return List<Rect>.generate(_choices.length, (index) {
      final row = index ~/ 2;
      if (_choices[index].isExit) {
        final tileTop = top + 5 * (tileHeight + rowGap);
        return Rect.fromLTWH(
          horizontalPadding,
          tileTop,
          size.width - horizontalPadding * 2,
          tileHeight,
        );
      }
      final column = index % 2;
      final left = horizontalPadding + column * (tileWidth + columnGap);
      final tileTop = top + row * (tileHeight + rowGap);
      return Rect.fromLTWH(left, tileTop, tileWidth, tileHeight);
    }, growable: false);
  }
}

class _DebugTileChoice {
  const _DebugTileChoice({
    required this.mode,
    required this.label,
    required this.icon,
  }) : isCancel = false,
       isExit = false;

  const _DebugTileChoice.cancel({required this.label, required this.icon})
    : mode = null,
      isCancel = true,
      isExit = false;

  const _DebugTileChoice.exit({required this.label, required this.icon})
    : mode = null,
      isCancel = false,
      isExit = true;

  final GestureDebugMode? mode;
  final String label;
  final IconData icon;
  final bool isCancel;
  final bool isExit;
}
