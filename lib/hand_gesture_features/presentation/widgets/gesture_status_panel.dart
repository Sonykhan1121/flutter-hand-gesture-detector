import 'package:flutter/material.dart';

/// Bottom status panel that summarizes the current hand and gesture state.
class GestureStatusPanel extends StatelessWidget {
  const GestureStatusPanel({
    super.key,
    required this.gestureText,
    required this.handText,
    required this.gestureConfidence,
    required this.detectedHandsCount,
  });

  final String gestureText;
  final String handText;
  final double gestureConfidence;
  final int detectedHandsCount;

  /// Builds the live gesture title and supporting detection details.
  @override
  Widget build(BuildContext context) {
    final hasGesture = gestureConfidence > 0;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          width: double.infinity,
          margin: const EdgeInsets.symmetric(horizontal: 16),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          decoration: BoxDecoration(
            color: hasGesture
                ? const Color(0xFF00FB46).withValues(alpha: 0.18)
                : Colors.black45,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: hasGesture ? const Color(0xFF00FB46) : Colors.white24,
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                hasGesture ? Icons.pan_tool_alt : Icons.back_hand,
                color: hasGesture ? const Color(0xFF00FB46) : Colors.white,
                size: 34,
              ),
              const SizedBox(height: 10),
              Text(
                gestureText,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: hasGesture ? const Color(0xFF00FB46) : Colors.white,
                  fontSize: 24,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                _subtitleText(),
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// Creates the smaller status line below the main gesture text.
  String _subtitleText() {
    if (detectedHandsCount == 0) {
      return 'Move your hand left, right, up, or down';
    }

    final parts = <String>['Hands: $detectedHandsCount'];

    if (handText.isNotEmpty) {
      parts.add(handText);
    }

    if (_isMovementGestureText(gestureText)) {
      parts.add('detected');
    } else if (gestureConfidence > 0) {
      parts.add('${(gestureConfidence * 100).toStringAsFixed(0)}%');
    }

    return parts.join('  •  ');
  }

  bool _isMovementGestureText(String text) {
    return text == 'Moving left' ||
        text == 'Moving right' ||
        text == 'Moving up' ||
        text == 'Moving down';
  }
}
