import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

import 'package:hand_detection/hand_detection.dart';
import 'package:opencv_dart/opencv_dart.dart' as cv;

import '../models/encoded_yolo_frame.dart';
import 'appearance_signature_extractor.dart';

/// Converts camera-plugin pixel planes into an upright JPEG for YOLO.predict.
class YoloCameraFrameEncoder {
  const YoloCameraFrameEncoder({
    required this.maxDimension,
    required this.jpegQuality,
  });

  final int maxDimension;
  final int jpegQuality;

  /// Performs pixel conversion and JPEG encoding outside Flutter's UI isolate.
  Future<EncodedYoloFrame?> encodeInBackground({
    required CameraPixelFrameData frame,
    required CameraFrameRotation? rotation,
  }) {
    return Isolate.run(
      () => encode(frame: frame, rotation: rotation),
      debugName: 'yolo-frame-encoder',
    );
  }

  EncodedYoloFrame? encode({
    required CameraPixelFrameData frame,
    required CameraFrameRotation? rotation,
  }) {
    if (frame.width <= 0 ||
        frame.height <= 0 ||
        frame.planes.isEmpty ||
        maxDimension <= 0) {
      return null;
    }

    final scale = math.min(
      1.0,
      maxDimension / math.max(frame.width, frame.height),
    );
    final width = math.max(1, (frame.width * scale).round());
    final height = math.max(1, (frame.height * scale).round());
    final bgr = Uint8List(width * height * 3);

    final converted = switch (frame.format) {
      CameraPixelFormat.bgra8888 => _copyBgra(frame, bgr, width, height, scale),
      CameraPixelFormat.nv21 => _copyNv21(frame, bgr, width, height, scale),
      CameraPixelFormat.yuv420 => _copyYuv420(frame, bgr, width, height, scale),
    };
    if (!converted) return null;

    final raw = cv.Mat.fromList(height, width, cv.MatType.CV_8UC3, bgr);
    cv.Mat upright = raw;
    cv.VecI32? encodeParameters;
    try {
      final rotationCode = switch (rotation) {
        CameraFrameRotation.cw90 => cv.ROTATE_90_CLOCKWISE,
        CameraFrameRotation.cw180 => cv.ROTATE_180,
        CameraFrameRotation.cw270 => cv.ROTATE_90_COUNTERCLOCKWISE,
        null => null,
      };
      if (rotationCode != null) upright = raw.rotate(rotationCode);

      encodeParameters = cv.VecI32.fromList([
        cv.IMWRITE_JPEG_QUALITY,
        jpegQuality.clamp(0, 100),
      ]);
      final (success, bytes) = cv.imencode(
        '.jpg',
        upright,
        params: encodeParameters,
      );
      if (!success || bytes.isEmpty) return null;
      return EncodedYoloFrame(
        jpegBytes: bytes,
        imageSize: Size(upright.cols.toDouble(), upright.rows.toDouble()),
      );
    } finally {
      encodeParameters?.dispose();
      if (!identical(upright, raw)) upright.dispose();
      raw.dispose();
    }
  }

  bool _copyBgra(
    CameraPixelFrameData frame,
    Uint8List output,
    int width,
    int height,
    double scale,
  ) {
    final plane = frame.planes.first;
    final pixelStride = math.max(4, plane.bytesPerPixel);
    for (var y = 0; y < height; y++) {
      final sourceY = math.min(frame.height - 1, (y / scale).floor());
      for (var x = 0; x < width; x++) {
        final sourceX = math.min(frame.width - 1, (x / scale).floor());
        final sourceIndex = sourceY * plane.bytesPerRow + sourceX * pixelStride;
        if (sourceIndex < 0 || sourceIndex + 2 >= plane.bytes.length) {
          return false;
        }
        final targetIndex = (y * width + x) * 3;
        output[targetIndex] = plane.bytes[sourceIndex];
        output[targetIndex + 1] = plane.bytes[sourceIndex + 1];
        output[targetIndex + 2] = plane.bytes[sourceIndex + 2];
      }
    }
    return true;
  }

  bool _copyNv21(
    CameraPixelFrameData frame,
    Uint8List output,
    int width,
    int height,
    double scale,
  ) {
    final plane = frame.planes.first;
    final chromaStart = plane.bytesPerRow * frame.height;
    for (var y = 0; y < height; y++) {
      final sourceY = math.min(frame.height - 1, (y / scale).floor());
      for (var x = 0; x < width; x++) {
        final sourceX = math.min(frame.width - 1, (x / scale).floor());
        final yIndex = sourceY * plane.bytesPerRow + sourceX;
        final chromaIndex =
            chromaStart +
            (sourceY ~/ 2) * plane.bytesPerRow +
            (sourceX ~/ 2) * 2;
        if (yIndex < 0 ||
            yIndex >= plane.bytes.length ||
            chromaIndex < 0 ||
            chromaIndex + 1 >= plane.bytes.length) {
          return false;
        }
        _writeYuvAsBgr(
          output,
          (y * width + x) * 3,
          plane.bytes[yIndex],
          plane.bytes[chromaIndex + 1],
          plane.bytes[chromaIndex],
        );
      }
    }
    return true;
  }

  bool _copyYuv420(
    CameraPixelFrameData frame,
    Uint8List output,
    int width,
    int height,
    double scale,
  ) {
    if (frame.planes.length < 3) return false;
    final yPlane = frame.planes[0];
    final uPlane = frame.planes[1];
    final vPlane = frame.planes[2];
    for (var y = 0; y < height; y++) {
      final sourceY = math.min(frame.height - 1, (y / scale).floor());
      for (var x = 0; x < width; x++) {
        final sourceX = math.min(frame.width - 1, (x / scale).floor());
        final yIndex =
            sourceY * yPlane.bytesPerRow + sourceX * yPlane.bytesPerPixel;
        final uvX = sourceX ~/ 2;
        final uvY = sourceY ~/ 2;
        final uIndex = uvY * uPlane.bytesPerRow + uvX * uPlane.bytesPerPixel;
        final vIndex = uvY * vPlane.bytesPerRow + uvX * vPlane.bytesPerPixel;
        if (yIndex < 0 ||
            yIndex >= yPlane.bytes.length ||
            uIndex < 0 ||
            uIndex >= uPlane.bytes.length ||
            vIndex < 0 ||
            vIndex >= vPlane.bytes.length) {
          return false;
        }
        _writeYuvAsBgr(
          output,
          (y * width + x) * 3,
          yPlane.bytes[yIndex],
          uPlane.bytes[uIndex],
          vPlane.bytes[vIndex],
        );
      }
    }
    return true;
  }

  void _writeYuvAsBgr(Uint8List output, int index, int y, int u, int v) {
    final yf = math.max(0, y - 16).toDouble();
    final uf = u - 128.0;
    final vf = v - 128.0;
    output[index] = (1.164 * yf + 2.017 * uf).round().clamp(0, 255);
    output[index + 1] = (1.164 * yf - 0.392 * uf - 0.813 * vf).round().clamp(
      0,
      255,
    );
    output[index + 2] = (1.164 * yf + 1.596 * vf).round().clamp(0, 255);
  }
}
