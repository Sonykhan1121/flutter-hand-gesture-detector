/// Open-palm detector output with both boolean state and confidence.
class OpenPalmGestureDetectionResult {
  const OpenPalmGestureDetectionResult({
    required this.isDetected,
    required this.confidence,
  });

  final bool isDetected;
  final double confidence;
}
