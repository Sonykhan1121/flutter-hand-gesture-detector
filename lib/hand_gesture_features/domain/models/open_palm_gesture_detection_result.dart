class OpenPalmGestureDetectionResult {
  const OpenPalmGestureDetectionResult({
    required this.isDetected,
    required this.confidence,
  });

  final bool isDetected;
  final double confidence;
}
