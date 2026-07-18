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
