import 'dart:ui';

import 'package:hand_detection/hand_detection.dart';

/// Maps an already-upright image-space rectangle into normalized display space.
Rect imageRectToDisplayBox({
  required Rect rect,
  required Size imageSize,
  required bool mirrorHorizontally,
}) {
  return cameraFrameRectToDisplayBox(
    rect: rect,
    imageSize: imageSize,
    rotation: null,
    mirrorHorizontally: mirrorHorizontally,
  );
}

/// Maps a raw camera-frame rectangle into normalized preview display space.
Rect cameraFrameRectToDisplayBox({
  required Rect rect,
  required Size imageSize,
  required CameraFrameRotation? rotation,
  required bool mirrorHorizontally,
}) {
  if (imageSize.width <= 0 || imageSize.height <= 0 || rect.isEmpty) {
    return Rect.zero;
  }

  final points = [
    cameraFramePointToDisplayPoint(
      point: Offset(rect.left, rect.top),
      imageSize: imageSize,
      rotation: rotation,
      mirrorHorizontally: mirrorHorizontally,
    ),
    cameraFramePointToDisplayPoint(
      point: Offset(rect.right, rect.top),
      imageSize: imageSize,
      rotation: rotation,
      mirrorHorizontally: mirrorHorizontally,
    ),
    cameraFramePointToDisplayPoint(
      point: Offset(rect.left, rect.bottom),
      imageSize: imageSize,
      rotation: rotation,
      mirrorHorizontally: mirrorHorizontally,
    ),
    cameraFramePointToDisplayPoint(
      point: Offset(rect.right, rect.bottom),
      imageSize: imageSize,
      rotation: rotation,
      mirrorHorizontally: mirrorHorizontally,
    ),
  ];

  var left = points.first.dx;
  var top = points.first.dy;
  var right = points.first.dx;
  var bottom = points.first.dy;

  for (final point in points.skip(1)) {
    if (point.dx < left) left = point.dx;
    if (point.dy < top) top = point.dy;
    if (point.dx > right) right = point.dx;
    if (point.dy > bottom) bottom = point.dy;
  }

  return Rect.fromLTRB(
    left.clamp(0.0, 1.0),
    top.clamp(0.0, 1.0),
    right.clamp(0.0, 1.0),
    bottom.clamp(0.0, 1.0),
  );
}

/// Maps one raw camera-frame point into normalized preview display space.
Offset cameraFramePointToDisplayPoint({
  required Offset point,
  required Size imageSize,
  required CameraFrameRotation? rotation,
  required bool mirrorHorizontally,
}) {
  if (imageSize.width <= 0 || imageSize.height <= 0) return Offset.zero;

  final normalizedPoint = Offset(
    (point.dx / imageSize.width).clamp(0.0, 1.0),
    (point.dy / imageSize.height).clamp(0.0, 1.0),
  );
  final rotatedPoint = _rotateNormalizedPoint(normalizedPoint, rotation);
  final displayPoint = mirrorHorizontally
      ? Offset(1.0 - rotatedPoint.dx, rotatedPoint.dy)
      : rotatedPoint;

  return Offset(
    displayPoint.dx.clamp(0.0, 1.0),
    displayPoint.dy.clamp(0.0, 1.0),
  );
}

Offset _rotateNormalizedPoint(Offset point, CameraFrameRotation? rotation) {
  switch (rotation) {
    case CameraFrameRotation.cw90:
      return Offset(1 - point.dy, point.dx);
    case CameraFrameRotation.cw180:
      return Offset(1 - point.dx, 1 - point.dy);
    case CameraFrameRotation.cw270:
      return Offset(point.dy, 1 - point.dx);
    case null:
      return point;
  }
}
