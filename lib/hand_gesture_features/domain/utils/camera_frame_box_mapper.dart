import 'dart:math' as math;
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

/// Maps a normalized preview rectangle back into normalized raw-frame space.
Rect displayRectToCameraFrameRect({
  required Rect displayRect,
  required CameraFrameRotation? rotation,
  required bool mirrorHorizontally,
}) {
  if (displayRect.isEmpty) return Rect.zero;
  final points = [
    displayPointToCameraFramePoint(
      point: displayRect.topLeft,
      rotation: rotation,
      mirrorHorizontally: mirrorHorizontally,
    ),
    displayPointToCameraFramePoint(
      point: displayRect.topRight,
      rotation: rotation,
      mirrorHorizontally: mirrorHorizontally,
    ),
    displayPointToCameraFramePoint(
      point: displayRect.bottomLeft,
      rotation: rotation,
      mirrorHorizontally: mirrorHorizontally,
    ),
    displayPointToCameraFramePoint(
      point: displayRect.bottomRight,
      rotation: rotation,
      mirrorHorizontally: mirrorHorizontally,
    ),
  ];
  final xs = points.map((point) => point.dx);
  final ys = points.map((point) => point.dy);
  return Rect.fromLTRB(
    xs.reduce(math.min).clamp(0.0, 1.0),
    ys.reduce(math.min).clamp(0.0, 1.0),
    xs.reduce(math.max).clamp(0.0, 1.0),
    ys.reduce(math.max).clamp(0.0, 1.0),
  );
}

/// Maps one normalized preview point back into normalized raw-frame space.
Offset displayPointToCameraFramePoint({
  required Offset point,
  required CameraFrameRotation? rotation,
  required bool mirrorHorizontally,
}) {
  final upright = mirrorHorizontally ? Offset(1 - point.dx, point.dy) : point;
  final raw = switch (rotation) {
    CameraFrameRotation.cw90 => Offset(upright.dy, 1 - upright.dx),
    CameraFrameRotation.cw180 => Offset(1 - upright.dx, 1 - upright.dy),
    CameraFrameRotation.cw270 => Offset(1 - upright.dy, upright.dx),
    null => upright,
  };
  return Offset(raw.dx.clamp(0.0, 1.0), raw.dy.clamp(0.0, 1.0));
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
  final displayPoint =
      mirrorHorizontally
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
