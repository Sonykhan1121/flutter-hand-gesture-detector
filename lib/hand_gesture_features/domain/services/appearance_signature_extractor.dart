import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

import 'package:camera/camera.dart';
import 'package:hand_detection/hand_detection.dart';

import '../models/appearance_signature.dart';

enum CameraPixelFormat { bgra8888, nv21, yuv420 }

class CameraPixelPlaneData {
  const CameraPixelPlaneData({
    required this.bytes,
    required this.bytesPerRow,
    required this.bytesPerPixel,
  });

  final Uint8List bytes;
  final int bytesPerRow;
  final int bytesPerPixel;
}

class CameraPixelFrameData {
  const CameraPixelFrameData({
    required this.width,
    required this.height,
    required this.format,
    required this.planes,
  });

  final int width;
  final int height;
  final CameraPixelFormat format;
  final List<CameraPixelPlaneData> planes;

  factory CameraPixelFrameData.fromCameraImage(
    CameraImage image, {
    required bool isBgra,
  }) {
    final format = isBgra
        ? CameraPixelFormat.bgra8888
        : image.planes.length == 1
        ? CameraPixelFormat.nv21
        : CameraPixelFormat.yuv420;

    return CameraPixelFrameData(
      width: image.width,
      height: image.height,
      format: format,
      planes: [
        for (final plane in image.planes)
          CameraPixelPlaneData(
            bytes: plane.bytes,
            bytesPerRow: plane.bytesPerRow,
            bytesPerPixel: plane.bytesPerPixel ?? 1,
          ),
      ],
    );
  }
}

/// Samples a target crop without decoding or copying the full camera frame.
class AppearanceSignatureExtractor {
  const AppearanceSignatureExtractor();

  AppearanceSignature? extract({
    required CameraPixelFrameData frame,
    required Rect displayBox,
    required CameraFrameRotation? rotation,
    required bool mirrorHorizontally,
  }) {
    if (frame.width <= 0 ||
        frame.height <= 0 ||
        displayBox.isEmpty ||
        frame.planes.isEmpty) {
      return null;
    }

    final crop = _centralCrop(displayBox);
    final colors = <_Rgb>[];
    final luminances = <double>[];
    const gridSize = 8;

    for (var row = 0; row < gridSize; row++) {
      for (var col = 0; col < gridSize; col++) {
        final displayPoint = Offset(
          crop.left + crop.width * ((col + 0.5) / gridSize),
          crop.top + crop.height * ((row + 0.5) / gridSize),
        );
        final rawPoint = _displayToRawPoint(
          displayPoint,
          rotation: rotation,
          mirrorHorizontally: mirrorHorizontally,
        );
        final color = _readPixel(frame, rawPoint);
        if (color == null) return null;
        colors.add(color);
        luminances.add(color.luminance);
      }
    }

    final histogram = List<double>.filled(32, 0);
    for (final color in colors) {
      final hsv = color.hsv;
      final hueBin = (hsv.$1 * 8).floor().clamp(0, 7);
      final saturationBin = (hsv.$2 * 4).floor().clamp(0, 3);
      histogram[hueBin * 4 + saturationBin]++;
    }
    for (var i = 0; i < histogram.length; i++) {
      histogram[i] /= colors.length;
    }

    final mean = luminances.reduce((a, b) => a + b) / luminances.length;
    return AppearanceSignature(
      hsvHistogram: List.unmodifiable(histogram),
      grayscaleHash: List.unmodifiable(
        luminances.map((value) => value >= mean),
      ),
      aspectRatio: displayBox.width / displayBox.height,
    );
  }

  Rect _centralCrop(Rect box) {
    final dx = box.width * 0.10;
    final dy = box.height * 0.10;
    return Rect.fromLTRB(
      (box.left + dx).clamp(0.0, 1.0),
      (box.top + dy).clamp(0.0, 1.0),
      (box.right - dx).clamp(0.0, 1.0),
      (box.bottom - dy).clamp(0.0, 1.0),
    );
  }

  Offset _displayToRawPoint(
    Offset displayPoint, {
    required CameraFrameRotation? rotation,
    required bool mirrorHorizontally,
  }) {
    final upright = mirrorHorizontally
        ? Offset(1 - displayPoint.dx, displayPoint.dy)
        : displayPoint;

    return switch (rotation) {
      CameraFrameRotation.cw90 => Offset(upright.dy, 1 - upright.dx),
      CameraFrameRotation.cw180 => Offset(1 - upright.dx, 1 - upright.dy),
      CameraFrameRotation.cw270 => Offset(1 - upright.dy, upright.dx),
      null => upright,
    };
  }

  _Rgb? _readPixel(CameraPixelFrameData frame, Offset normalizedPoint) {
    final x = (normalizedPoint.dx.clamp(0.0, 1.0) * (frame.width - 1)).round();
    final y = (normalizedPoint.dy.clamp(0.0, 1.0) * (frame.height - 1)).round();

    return switch (frame.format) {
      CameraPixelFormat.bgra8888 => _readBgra(frame, x, y),
      CameraPixelFormat.nv21 => _readNv21(frame, x, y),
      CameraPixelFormat.yuv420 => _readYuv420(frame, x, y),
    };
  }

  _Rgb? _readBgra(CameraPixelFrameData frame, int x, int y) {
    final plane = frame.planes.first;
    final index = y * plane.bytesPerRow + x * plane.bytesPerPixel;
    if (index < 0 || index + 2 >= plane.bytes.length) return null;
    return _Rgb(
      plane.bytes[index + 2],
      plane.bytes[index + 1],
      plane.bytes[index],
    );
  }

  _Rgb? _readNv21(CameraPixelFrameData frame, int x, int y) {
    final plane = frame.planes.first;
    final yIndex = y * plane.bytesPerRow + x;
    final chromaStart = plane.bytesPerRow * frame.height;
    final chromaIndex =
        chromaStart + (y ~/ 2) * plane.bytesPerRow + (x ~/ 2) * 2;
    if (yIndex < 0 ||
        chromaIndex < 0 ||
        chromaIndex + 1 >= plane.bytes.length) {
      return null;
    }
    return _yuvToRgb(
      plane.bytes[yIndex],
      plane.bytes[chromaIndex + 1],
      plane.bytes[chromaIndex],
    );
  }

  _Rgb? _readYuv420(CameraPixelFrameData frame, int x, int y) {
    if (frame.planes.length < 3) return null;
    final yPlane = frame.planes[0];
    final uPlane = frame.planes[1];
    final vPlane = frame.planes[2];
    final yIndex = y * yPlane.bytesPerRow + x * yPlane.bytesPerPixel;
    final uvX = x ~/ 2;
    final uvY = y ~/ 2;
    final uIndex = uvY * uPlane.bytesPerRow + uvX * uPlane.bytesPerPixel;
    final vIndex = uvY * vPlane.bytesPerRow + uvX * vPlane.bytesPerPixel;
    if (yIndex < 0 ||
        yIndex >= yPlane.bytes.length ||
        uIndex < 0 ||
        uIndex >= uPlane.bytes.length ||
        vIndex < 0 ||
        vIndex >= vPlane.bytes.length) {
      return null;
    }
    return _yuvToRgb(
      yPlane.bytes[yIndex],
      uPlane.bytes[uIndex],
      vPlane.bytes[vIndex],
    );
  }

  _Rgb _yuvToRgb(int y, int u, int v) {
    final yf = math.max(0, y - 16).toDouble();
    final uf = u - 128.0;
    final vf = v - 128.0;
    return _Rgb(
      (1.164 * yf + 1.596 * vf).round().clamp(0, 255),
      (1.164 * yf - 0.392 * uf - 0.813 * vf).round().clamp(0, 255),
      (1.164 * yf + 2.017 * uf).round().clamp(0, 255),
    );
  }
}

class _Rgb {
  const _Rgb(this.r, this.g, this.b);

  final int r;
  final int g;
  final int b;

  double get luminance => 0.299 * r + 0.587 * g + 0.114 * b;

  (double, double, double) get hsv {
    final rf = r / 255.0;
    final gf = g / 255.0;
    final bf = b / 255.0;
    final maxValue = math.max(rf, math.max(gf, bf));
    final minValue = math.min(rf, math.min(gf, bf));
    final delta = maxValue - minValue;
    var hue = 0.0;
    if (delta > 0) {
      if (maxValue == rf) {
        hue = ((gf - bf) / delta) % 6;
      } else if (maxValue == gf) {
        hue = (bf - rf) / delta + 2;
      } else {
        hue = (rf - gf) / delta + 4;
      }
      hue /= 6;
      if (hue < 0) hue += 1;
    }
    final saturation = maxValue == 0 ? 0.0 : delta / maxValue;
    return (hue, saturation, maxValue);
  }
}
