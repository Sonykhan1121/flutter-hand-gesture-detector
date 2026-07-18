import 'dart:isolate';
import 'dart:typed_data';

import 'package:camera/camera.dart';

import '../services/appearance_signature_extractor.dart';

/// Converts one Android camera image to the packed NV21 format ML Kit expects.
Uint8List? encodeCameraImageAsNv21(CameraImage image) {
  return encodeNv21(CameraPixelFrameData.fromCameraImage(image, isBgra: false));
}

/// Converts transferable camera-plane data to packed NV21 bytes.
Uint8List? encodeNv21(CameraPixelFrameData frame) {
  if (frame.format == CameraPixelFormat.nv21 && frame.planes.length == 1) {
    return frame.planes.first.bytes;
  }
  if (frame.format != CameraPixelFormat.yuv420 ||
      frame.planes.length < 3 ||
      frame.width.isOdd ||
      frame.height.isOdd) {
    return null;
  }

  final width = frame.width;
  final height = frame.height;
  final yPlane = frame.planes[0];
  final uPlane = frame.planes[1];
  final vPlane = frame.planes[2];
  final ySize = width * height;
  final bytes = Uint8List(ySize + width * height ~/ 2);

  for (var row = 0; row < height; row++) {
    for (var column = 0; column < width; column++) {
      bytes[row * width + column] = _planeByte(yPlane, row, column);
    }
  }
  for (var row = 0; row < height ~/ 2; row++) {
    for (var column = 0; column < width ~/ 2; column++) {
      final outputIndex = ySize + row * width + column * 2;
      bytes[outputIndex] = _planeByte(vPlane, row, column);
      bytes[outputIndex + 1] = _planeByte(uPlane, row, column);
    }
  }
  return bytes;
}

/// Runs NV21 conversion outside Flutter's UI isolate.
Future<Uint8List?> encodeNv21InBackground(CameraPixelFrameData frame) {
  return Isolate.run(() => encodeNv21(frame), debugName: 'ml-kit-nv21-encoder');
}

int _planeByte(CameraPixelPlaneData plane, int row, int column) {
  final index = row * plane.bytesPerRow + column * plane.bytesPerPixel;
  if (index < 0 || index >= plane.bytes.length) return 128;
  return plane.bytes[index];
}
