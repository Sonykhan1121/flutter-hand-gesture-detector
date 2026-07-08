import 'package:flutter/material.dart';

/// Floating camera zoom controller shown after gesture zoom is detected.
///
/// Keep this widget UI-only. The parent screen owns camera zoom state and
/// applies zoom level changes to CameraController.
class ZoomControlOverlay extends StatelessWidget {
  const ZoomControlOverlay({
    super.key,
    required this.currentZoomLevel,
    required this.minZoomLevel,
    required this.maxZoomLevel,
    required this.onZoomChanged,
    required this.onZoomIncrease,
    required this.onZoomDecrease,
    required this.onZoomReset,
    required this.onInteractionStart,
    required this.onInteractionEnd,
    required this.onClose,
  });

  final double currentZoomLevel;
  final double minZoomLevel;
  final double maxZoomLevel;
  final ValueChanged<double> onZoomChanged;
  final VoidCallback onZoomIncrease;
  final VoidCallback onZoomDecrease;
  final VoidCallback onZoomReset;
  final VoidCallback onInteractionStart;
  final VoidCallback onInteractionEnd;
  final VoidCallback onClose;

  static const _accentColor = Color(0xFF00FB46);

  /// True when the active camera reports more than one zoom level.
  bool get _isZoomSupported => maxZoomLevel > minZoomLevel;

  @override
  /// Builds the floating zoom slider and +/-/reset controls.
  Widget build(BuildContext context) {
    final safeCurrentZoom = currentZoomLevel
        .clamp(minZoomLevel, maxZoomLevel)
        .toDouble();
    final divisionCount = (((maxZoomLevel - minZoomLevel) * 10).round())
        .clamp(1, 120)
        .toInt();

    return Material(
      color: Colors.transparent,
      child: Container(
        width: 76,
        padding: const EdgeInsets.fromLTRB(8, 8, 8, 10),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.72),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: Colors.white24),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.28),
              blurRadius: 18,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: _isZoomSupported
            ? Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Expanded(
                        child: Text(
                          '${safeCurrentZoom.toStringAsFixed(1)}x',
                          textAlign: TextAlign.center,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                            fontFeatures: [FontFeature.tabularFigures()],
                          ),
                        ),
                      ),
                      GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: onClose,
                        child: const Padding(
                          padding: EdgeInsets.all(2),
                          child: Icon(
                            Icons.close_rounded,
                            color: Colors.white70,
                            size: 16,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  _ZoomCircleButton(
                    icon: Icons.add_rounded,
                    onTap: onZoomIncrease,
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    height: 150,
                    width: 42,
                    child: RotatedBox(
                      quarterTurns: 3,
                      child: SliderTheme(
                        data: SliderTheme.of(context).copyWith(
                          activeTrackColor: _accentColor,
                          inactiveTrackColor: Colors.white24,
                          thumbColor: Colors.white,
                          overlayColor: _accentColor.withValues(alpha: 0.18),
                          trackHeight: 3.5,
                          thumbShape: const RoundSliderThumbShape(
                            enabledThumbRadius: 8,
                          ),
                          overlayShape: const RoundSliderOverlayShape(
                            overlayRadius: 15,
                          ),
                        ),
                        child: Slider(
                          value: safeCurrentZoom,
                          min: minZoomLevel,
                          max: maxZoomLevel,
                          divisions: divisionCount,
                          onChangeStart: (_) => onInteractionStart(),
                          onChanged: onZoomChanged,
                          onChangeEnd: (_) => onInteractionEnd(),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  _ZoomCircleButton(
                    icon: Icons.remove_rounded,
                    onTap: onZoomDecrease,
                  ),
                  const SizedBox(height: 8),
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: onZoomReset,
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 7),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.10),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.white12),
                      ),
                      child: const Text(
                        'Reset',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ),
                ],
              )
            : const Padding(
                padding: EdgeInsets.symmetric(vertical: 10),
                child: Text(
                  'Zoom unavailable',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
      ),
    );
  }
}

/// Small circular tap target for zoom increase/decrease buttons.
class _ZoomCircleButton extends StatelessWidget {
  const _ZoomCircleButton({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  /// Builds the circular icon-only zoom button.
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        width: 34,
        height: 34,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.12),
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white24),
        ),
        child: Icon(icon, color: Colors.white, size: 22),
      ),
    );
  }
}
