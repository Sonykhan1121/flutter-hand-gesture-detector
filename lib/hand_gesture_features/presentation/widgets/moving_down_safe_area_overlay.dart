import 'package:flutter/material.dart';

import '../../domain/models/moving_down_capture_contract.dart';

class MovingDownSafeAreaOverlay extends StatelessWidget {
  const MovingDownSafeAreaOverlay({
    super.key,
    required this.canvasSize,
    required this.detectedHandLabel,
    required this.handInside,
  });

  final Size canvasSize;
  final String? detectedHandLabel;
  final bool handInside;

  @override
  Widget build(BuildContext context) {
    final hasHand = detectedHandLabel != null;
    final safetyColor = !hasHand
        ? Colors.white54
        : handInside
        ? Colors.greenAccent
        : const Color(0xFFFF453A);
    return IgnorePointer(
      child: Stack(
        fit: StackFit.expand,
        children: [
          Padding(
            padding: EdgeInsets.symmetric(
              horizontal: canvasSize.width * movingDownSafeAreaMinimum,
              vertical: canvasSize.height * movingDownSafeAreaMinimum,
            ),
            child: DecoratedBox(
              key: const Key('movingDownSafeAreaBoundary'),
              decoration: BoxDecoration(
                border: Border.all(color: safetyColor, width: 2.5),
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
          Positioned(
            left: 12,
            right: 12,
            bottom: 12,
            child: Container(
              key: const Key('movingDownLiveHandSafetyStatus'),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.72),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: safetyColor),
              ),
              child: Text(
                !hasHand
                    ? 'Place the complete hand inside the safety box'
                    : handInside
                    ? '$detectedHandLabel hand · fully inside'
                    : '$detectedHandLabel hand · move away from the edge',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: safetyColor,
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
