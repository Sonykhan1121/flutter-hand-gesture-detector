import 'dart:ui';

import 'package:camera/camera.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart'
    as ml_face;
import 'package:object_detection/object_detection.dart';

import '../../domain/utils/android_nv21_encoder.dart';

/// Maps camera-frame rotation to the equivalent ML Kit input rotation.
ml_face.InputImageRotation mlKitInputRotation(CameraFrameRotation? rotation) {
  return switch (rotation) {
    CameraFrameRotation.cw90 => ml_face.InputImageRotation.rotation90deg,
    CameraFrameRotation.cw180 => ml_face.InputImageRotation.rotation180deg,
    CameraFrameRotation.cw270 => ml_face.InputImageRotation.rotation270deg,
    null => ml_face.InputImageRotation.rotation0deg,
  };
}

/// Builds the platform-specific ML Kit face-detector input image.
ml_face.InputImage? mlKitFaceInputImage(
  CameraImage image, {
  required CameraFrameRotation? rotation,
  required bool isAndroid,
  required bool isIOS,
}) {
  if (isAndroid) {
    final bytes = encodeCameraImageAsNv21(image);
    if (bytes == null) return null;
    return ml_face.InputImage.fromBytes(
      bytes: bytes,
      metadata: ml_face.InputImageMetadata(
        size: Size(image.width.toDouble(), image.height.toDouble()),
        rotation: mlKitInputRotation(rotation),
        format: ml_face.InputImageFormat.nv21,
        bytesPerRow: image.planes.first.bytesPerRow,
      ),
    );
  }

  if (isIOS) {
    final format = ml_face.InputImageFormatValue.fromRawValue(image.format.raw);
    if (format != ml_face.InputImageFormat.bgra8888 ||
        image.planes.length != 1) {
      return null;
    }
    final plane = image.planes.first;
    return ml_face.InputImage.fromBytes(
      bytes: plane.bytes,
      metadata: ml_face.InputImageMetadata(
        size: Size(image.width.toDouble(), image.height.toDouble()),
        rotation: mlKitInputRotation(rotation),
        format: format!,
        bytesPerRow: plane.bytesPerRow,
      ),
    );
  }

  return null;
}

/// Maps an ML Kit rectangle to normalized preview coordinates.
Rect mlKitDisplayRect(
  Rect rect, {
  required Size imageSize,
  required ml_face.InputImageRotation rotation,
  required bool isIOS,
  required bool mirrorHorizontally,
}) {
  final topLeft = _mlKitDisplayPoint(
    Offset(rect.left, rect.top),
    imageSize: imageSize,
    rotation: rotation,
    isIOS: isIOS,
    mirrorHorizontally: mirrorHorizontally,
  );
  final bottomRight = _mlKitDisplayPoint(
    Offset(rect.right, rect.bottom),
    imageSize: imageSize,
    rotation: rotation,
    isIOS: isIOS,
    mirrorHorizontally: mirrorHorizontally,
  );

  return Rect.fromLTRB(
    (topLeft.dx < bottomRight.dx ? topLeft.dx : bottomRight.dx).clamp(0, 1),
    (topLeft.dy < bottomRight.dy ? topLeft.dy : bottomRight.dy).clamp(0, 1),
    (topLeft.dx > bottomRight.dx ? topLeft.dx : bottomRight.dx).clamp(0, 1),
    (topLeft.dy > bottomRight.dy ? topLeft.dy : bottomRight.dy).clamp(0, 1),
  );
}

Offset _mlKitDisplayPoint(
  Offset point, {
  required Size imageSize,
  required ml_face.InputImageRotation rotation,
  required bool isIOS,
  required bool mirrorHorizontally,
}) {
  final normalizedX = switch (rotation) {
    ml_face.InputImageRotation.rotation90deg =>
      point.dx / (isIOS ? imageSize.width : imageSize.height),
    ml_face.InputImageRotation.rotation270deg =>
      1 - point.dx / (isIOS ? imageSize.width : imageSize.height),
    ml_face.InputImageRotation.rotation0deg ||
    ml_face.InputImageRotation.rotation180deg =>
      mirrorHorizontally
          ? 1 - point.dx / imageSize.width
          : point.dx / imageSize.width,
  };
  final normalizedY = switch (rotation) {
    ml_face.InputImageRotation.rotation90deg ||
    ml_face.InputImageRotation.rotation270deg =>
      point.dy / (isIOS ? imageSize.height : imageSize.width),
    ml_face.InputImageRotation.rotation0deg ||
    ml_face.InputImageRotation.rotation180deg => point.dy / imageSize.height,
  };

  return Offset(normalizedX.clamp(0, 1), normalizedY.clamp(0, 1));
}
