import 'package:flutter/material.dart';

/// Compact status displayed while a Detect My Face lock is being reacquired.
class FaceReacquisitionStatusOverlay extends StatelessWidget {
  const FaceReacquisitionStatusOverlay.waiting({
    required this.remaining,
    super.key,
  }) : hasTimedOut = false;

  const FaceReacquisitionStatusOverlay.timedOut({super.key})
    : remaining = Duration.zero,
      hasTimedOut = true;

  final Duration remaining;
  final bool hasTimedOut;

  @override
  Widget build(BuildContext context) {
    final remainingSeconds = remaining.inMilliseconds / 1000;
    final message = hasTimedOut
        ? 'Face lost - use Detect My Face again'
        : 'Face lost - waiting (${remainingSeconds.toStringAsFixed(1)}s)';

    return Semantics(
      liveRegion: true,
      label: message,
      child: Container(
        key: const Key('faceReacquisitionStatusOverlay'),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        decoration: BoxDecoration(
          color: hasTimedOut
              ? Colors.red.shade800.withValues(alpha: 0.88)
              : Colors.orange.shade800.withValues(alpha: 0.88),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: Colors.white24),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              hasTimedOut
                  ? Icons.person_off_outlined
                  : Icons.person_search_outlined,
              color: Colors.white,
              size: 18,
            ),
            const SizedBox(width: 8),
            Text(
              message,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
