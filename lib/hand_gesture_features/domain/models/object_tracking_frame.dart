import 'dart:typed_data';
import 'dart:ui';

import 'package:hand_detection/hand_detection.dart';

/// Downscaled grayscale camera frame used by sparse optical flow.
class ObjectTrackingFrame {
  const ObjectTrackingFrame({
    required this.frameId,
    required this.capturedAt,
    required this.width,
    required this.height,
    required this.grayscaleBytes,
    required this.rotation,
    required this.mirrorHorizontally,
  });

  final int frameId;
  final DateTime capturedAt;
  final int width;
  final int height;
  final Uint8List grayscaleBytes;
  final CameraFrameRotation? rotation;
  final bool mirrorHorizontally;

  Size get size => Size(width.toDouble(), height.toDouble());
}
