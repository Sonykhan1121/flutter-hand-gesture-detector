import 'dart:typed_data';
import 'dart:ui';

/// One upright, encoded camera frame accepted by Ultralytics YOLO.
class EncodedYoloFrame {
  const EncodedYoloFrame({required this.jpegBytes, required this.imageSize});

  final Uint8List jpegBytes;
  final Size imageSize;
}
