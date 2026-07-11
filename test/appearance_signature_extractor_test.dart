import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:gesture_detector/hand_gesture_features/domain/services/appearance_signature_extractor.dart';
import 'package:hand_detection/hand_detection.dart';

void main() {
  const extractor = AppearanceSignatureExtractor();

  test('extracts an 8x8 signature from BGRA pixels', () {
    final signature = extractor.extract(
      frame: _bgraFrame(16, 16, (x, y) => const _Color(255, 0, 0)),
      displayBox: const Rect.fromLTWH(0, 0, 1, 1),
      rotation: null,
      mirrorHorizontally: false,
    );

    expect(signature, isNotNull);
    expect(signature!.grayscaleHash, hasLength(64));
    expect(signature.hsvHistogram, hasLength(32));
    expect(signature.hsvHistogram.reduce((a, b) => a + b), closeTo(1, 0.0001));
  });

  test('front-camera mirroring samples the opposite raw side', () {
    final frame = _bgraFrame(
      16,
      16,
      (x, y) => x < 8 ? const _Color(255, 0, 0) : const _Color(0, 0, 255),
    );
    final leftBox = const Rect.fromLTWH(0, 0, 0.45, 1);
    final rawLeft = extractor.extract(
      frame: frame,
      displayBox: leftBox,
      rotation: null,
      mirrorHorizontally: false,
    )!;
    final mirroredLeft = extractor.extract(
      frame: frame,
      displayBox: leftBox,
      rotation: null,
      mirrorHorizontally: true,
    )!;

    expect(rawLeft.histogramSimilarity(mirroredLeft), lessThan(0.2));
  });

  test('rotation maps upright display samples back to the raw frame', () {
    final frame = _bgraFrame(
      16,
      16,
      (x, y) => y < 8 ? const _Color(255, 0, 0) : const _Color(0, 0, 255),
    );
    final displayLeftAfterCw90 = extractor.extract(
      frame: frame,
      displayBox: const Rect.fromLTWH(0, 0, 0.45, 1),
      rotation: CameraFrameRotation.cw90,
      mirrorHorizontally: false,
    )!;
    final rawBottom = extractor.extract(
      frame: frame,
      displayBox: const Rect.fromLTWH(0, 0.55, 1, 0.45),
      rotation: null,
      mirrorHorizontally: false,
    )!;

    expect(
      displayLeftAfterCw90.histogramSimilarity(rawBottom),
      closeTo(1, 0.01),
    );
  });

  test('supports Android three-plane YUV420 frames', () {
    final signature = extractor.extract(
      frame: CameraPixelFrameData(
        width: 8,
        height: 8,
        format: CameraPixelFormat.yuv420,
        planes: [
          CameraPixelPlaneData(
            bytes: Uint8List.fromList(List<int>.filled(64, 128)),
            bytesPerRow: 8,
            bytesPerPixel: 1,
          ),
          CameraPixelPlaneData(
            bytes: Uint8List.fromList(List<int>.filled(16, 128)),
            bytesPerRow: 4,
            bytesPerPixel: 1,
          ),
          CameraPixelPlaneData(
            bytes: Uint8List.fromList(List<int>.filled(16, 128)),
            bytesPerRow: 4,
            bytesPerPixel: 1,
          ),
        ],
      ),
      displayBox: const Rect.fromLTWH(0, 0, 1, 1),
      rotation: null,
      mirrorHorizontally: false,
    );

    expect(signature, isNotNull);
    expect(signature!.grayscaleHash, everyElement(isTrue));
  });

  test('supports single-plane NV21 frames', () {
    final bytes = Uint8List(8 * 8 + 8 * 4);
    bytes.fillRange(0, 64, 128);
    bytes.fillRange(64, bytes.length, 128);
    final signature = extractor.extract(
      frame: CameraPixelFrameData(
        width: 8,
        height: 8,
        format: CameraPixelFormat.nv21,
        planes: [
          CameraPixelPlaneData(bytes: bytes, bytesPerRow: 8, bytesPerPixel: 1),
        ],
      ),
      displayBox: const Rect.fromLTWH(0, 0, 1, 1),
      rotation: null,
      mirrorHorizontally: false,
    );

    expect(signature, isNotNull);
    expect(signature!.grayscaleHash, everyElement(isTrue));
  });
}

CameraPixelFrameData _bgraFrame(
  int width,
  int height,
  _Color Function(int x, int y) colorAt,
) {
  final bytes = Uint8List(width * height * 4);
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      final color = colorAt(x, y);
      final index = (y * width + x) * 4;
      bytes[index] = color.b;
      bytes[index + 1] = color.g;
      bytes[index + 2] = color.r;
      bytes[index + 3] = 255;
    }
  }
  return CameraPixelFrameData(
    width: width,
    height: height,
    format: CameraPixelFormat.bgra8888,
    planes: [
      CameraPixelPlaneData(
        bytes: bytes,
        bytesPerRow: width * 4,
        bytesPerPixel: 4,
      ),
    ],
  );
}

class _Color {
  const _Color(this.r, this.g, this.b);

  final int r;
  final int g;
  final int b;
}
