import 'dart:math' as math;

/// Lightweight visual fingerprint captured from the center of a target box.
class AppearanceSignature {
  const AppearanceSignature({
    required this.hsvHistogram,
    required this.grayscaleHash,
    required this.aspectRatio,
  });

  final List<double> hsvHistogram;
  final List<bool> grayscaleHash;
  final double aspectRatio;

  double histogramSimilarity(AppearanceSignature other) {
    if (hsvHistogram.length != other.hsvHistogram.length ||
        hsvHistogram.isEmpty) {
      return 0;
    }

    var intersection = 0.0;
    for (var i = 0; i < hsvHistogram.length; i++) {
      intersection += math.min(hsvHistogram[i], other.hsvHistogram[i]);
    }
    return intersection.clamp(0.0, 1.0);
  }

  double hashSimilarity(AppearanceSignature other) {
    if (grayscaleHash.length != other.grayscaleHash.length ||
        grayscaleHash.isEmpty) {
      return 0;
    }

    var matches = 0;
    for (var i = 0; i < grayscaleHash.length; i++) {
      if (grayscaleHash[i] == other.grayscaleHash[i]) matches++;
    }
    return matches / grayscaleHash.length;
  }

  double aspectRatioSimilarity(AppearanceSignature other) {
    if (!aspectRatio.isFinite ||
        !other.aspectRatio.isFinite ||
        aspectRatio <= 0 ||
        other.aspectRatio <= 0) {
      return 0;
    }
    return math.min(aspectRatio, other.aspectRatio) /
        math.max(aspectRatio, other.aspectRatio);
  }

  double compositeSimilarity(AppearanceSignature other) {
    return histogramSimilarity(other) * 0.55 +
        hashSimilarity(other) * 0.30 +
        aspectRatioSimilarity(other) * 0.15;
  }
}
