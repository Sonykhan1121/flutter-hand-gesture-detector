import 'dart:math' as math;
import 'dart:ui';

/// Returns the camera preview size with its long edge aligned to the screen.
///
/// Camera plugins normally report the sensor preview in landscape order even
/// while the UI is portrait. Keeping this decision in one place ensures the
/// preview and every painter share the same 9:16 / 16:9 canvas.
Size orientedCameraPreviewSize({
  required Size? rawPreviewSize,
  required bool isLandscape,
}) {
  final validSize =
      rawPreviewSize != null &&
      rawPreviewSize.width.isFinite &&
      rawPreviewSize.height.isFinite &&
      rawPreviewSize.width > 0 &&
      rawPreviewSize.height > 0;
  final source = validSize ? rawPreviewSize : const Size(16, 9);
  final shortSide = source.shortestSide;
  final longSide = source.longestSide;
  return isLandscape ? Size(longSide, shortSide) : Size(shortSide, longSide);
}

/// Fits a preview into the available viewport without changing its ratio.
Size fittedCameraPreviewSize({
  required Size viewportSize,
  required Size previewSize,
}) {
  if (viewportSize.isEmpty || previewSize.isEmpty) return Size.zero;

  final scale =
      (viewportSize.width / previewSize.width) <
              (viewportSize.height / previewSize.height)
          ? viewportSize.width / previewSize.width
          : viewportSize.height / previewSize.height;
  return Size(previewSize.width * scale, previewSize.height * scale);
}

/// Returns the fitted camera-card size while moving from 9:16 to 16:9.
Size interpolatedCameraPreviewSize({
  required Size viewportSize,
  required Size? rawPreviewSize,
  required double progress,
}) {
  final portrait = fittedCameraPreviewSize(
    viewportSize: viewportSize,
    previewSize: orientedCameraPreviewSize(
      rawPreviewSize: rawPreviewSize,
      isLandscape: false,
    ),
  );
  final landscape = fittedCameraPreviewSize(
    viewportSize: viewportSize,
    previewSize: orientedCameraPreviewSize(
      rawPreviewSize: rawPreviewSize,
      isLandscape: true,
    ),
  );
  return Size.lerp(portrait, landscape, progress.clamp(0.0, 1.0))!;
}

/// Fades overlays out at the mapping switch, then fades them back in.
double cameraOverlayOpacity(double progress) {
  final normalized = progress.clamp(0.0, 1.0);
  return ((normalized - 0.5).abs() * 2).clamp(0.0, 1.0);
}

/// Switches painter coordinates only while the overlay is fully hidden.
int cameraPreviewQuarterTurns(double progress) => progress >= 0.5 ? 1 : 0;

/// Restores the Android recording texture to upright screen coordinates.
///
/// On the affected Android camera path, switching from the image stream to
/// video recording exposes the sensor texture one quarter-turn clockwise.
/// iOS and the normal Android preview do not need this correction.
int recordingCameraPreviewQuarterTurns({
  required bool isAndroid,
  required bool isRecordingPreview,
}) => isAndroid && isRecordingPreview ? 3 : 0;

/// Rotates a normalized preview point clockwise without touching detector data.
Offset rotateNormalizedDisplayPoint(Offset point, int quarterTurns) {
  switch (quarterTurns % 4) {
    case 1:
      return Offset(1 - point.dy, point.dx);
    case 2:
      return Offset(1 - point.dx, 1 - point.dy);
    case 3:
      return Offset(point.dy, 1 - point.dx);
    default:
      return point;
  }
}

/// Maps one detector-space point onto the exact live-preview canvas.
///
/// Normal preview mirrors before rotation. Recording preview follows the
/// cover-fitted painter and rotates before mirroring.
Offset? detectionPointToPreviewCanvas({
  required Offset sourcePoint,
  required Size detectionImageSize,
  required Size canvasSize,
  required bool mirrorHorizontally,
  required int previewQuarterTurns,
  required bool useRecordingPreviewMapping,
}) {
  if (!sourcePoint.dx.isFinite ||
      !sourcePoint.dy.isFinite ||
      !detectionImageSize.width.isFinite ||
      !detectionImageSize.height.isFinite ||
      detectionImageSize.width <= 0 ||
      detectionImageSize.height <= 0 ||
      !canvasSize.width.isFinite ||
      !canvasSize.height.isFinite ||
      canvasSize.width <= 0 ||
      canvasSize.height <= 0) {
    return null;
  }

  final requestedTurns = previewQuarterTurns % 4;
  final effectiveTurns =
      useRecordingPreviewMapping
          ? _bestPreviewQuarterTurns(
            imageSize: detectionImageSize,
            canvasSize: canvasSize,
            requestedTurns: requestedTurns,
          )
          : requestedTurns;
  final normalized = Offset(
    sourcePoint.dx / detectionImageSize.width,
    sourcePoint.dy / detectionImageSize.height,
  );

  if (!useRecordingPreviewMapping) {
    final mirrored =
        mirrorHorizontally
            ? Offset(1 - normalized.dx, normalized.dy)
            : normalized;
    final rotated = rotateNormalizedDisplayPoint(mirrored, effectiveTurns);
    return Offset(
      rotated.dx * canvasSize.width,
      rotated.dy * canvasSize.height,
    );
  }

  final rotated = rotateNormalizedDisplayPoint(normalized, effectiveTurns);
  final mirrored =
      mirrorHorizontally ? Offset(1 - rotated.dx, rotated.dy) : rotated;
  final sourceSize =
      effectiveTurns.isOdd
          ? Size(detectionImageSize.height, detectionImageSize.width)
          : detectionImageSize;
  final scale = math.max(
    canvasSize.width / sourceSize.width,
    canvasSize.height / sourceSize.height,
  );
  final fittedSize = sourceSize * scale;
  return Offset(
    (canvasSize.width - fittedSize.width) / 2 +
        mirrored.dx * sourceSize.width * scale,
    (canvasSize.height - fittedSize.height) / 2 +
        mirrored.dy * sourceSize.height * scale,
  );
}

int _bestPreviewQuarterTurns({
  required Size imageSize,
  required Size canvasSize,
  required int requestedTurns,
}) {
  final normalDifference =
      ((imageSize.width / imageSize.height) -
              (canvasSize.width / canvasSize.height))
          .abs();
  final rotatedSize =
      requestedTurns.isOdd
          ? Size(imageSize.height, imageSize.width)
          : imageSize;
  final rotatedDifference =
      ((rotatedSize.width / rotatedSize.height) -
              (canvasSize.width / canvasSize.height))
          .abs();
  return rotatedDifference < normalDifference ? requestedTurns : 0;
}

/// Rotates a normalized preview rectangle clockwise around the preview.
Rect rotateNormalizedDisplayRect(Rect rect, int quarterTurns) {
  if (rect.isEmpty) return Rect.zero;
  final corners = <Offset>[
    rotateNormalizedDisplayPoint(rect.topLeft, quarterTurns),
    rotateNormalizedDisplayPoint(rect.topRight, quarterTurns),
    rotateNormalizedDisplayPoint(rect.bottomLeft, quarterTurns),
    rotateNormalizedDisplayPoint(rect.bottomRight, quarterTurns),
  ];
  final xs = corners.map((point) => point.dx);
  final ys = corners.map((point) => point.dy);
  return Rect.fromLTRB(
    xs.reduce((a, b) => a < b ? a : b),
    ys.reduce((a, b) => a < b ? a : b),
    xs.reduce((a, b) => a > b ? a : b),
    ys.reduce((a, b) => a > b ? a : b),
  );
}

/// Aspect ratio for the shared camera/overlay canvas.
double orientedCameraPreviewAspectRatio({
  required Size? rawPreviewSize,
  required bool isLandscape,
}) {
  final size = orientedCameraPreviewSize(
    rawPreviewSize: rawPreviewSize,
    isLandscape: isLandscape,
  );
  return size.width / size.height;
}

/// Scales a normalized detector box onto the shared preview/painter canvas.
Rect normalizedDisplayRectToCanvasRect(
  Rect box,
  Size canvasSize, {
  int previewQuarterTurns = 0,
}) {
  if (box.isEmpty || canvasSize.width <= 0 || canvasSize.height <= 0) {
    return Rect.zero;
  }
  final displayBox = rotateNormalizedDisplayRect(box, previewQuarterTurns);
  return Rect.fromLTRB(
    (displayBox.left * canvasSize.width).clamp(0.0, canvasSize.width),
    (displayBox.top * canvasSize.height).clamp(0.0, canvasSize.height),
    (displayBox.right * canvasSize.width).clamp(0.0, canvasSize.width),
    (displayBox.bottom * canvasSize.height).clamp(0.0, canvasSize.height),
  );
}
