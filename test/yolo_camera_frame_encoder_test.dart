import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:gesture_detector/hand_gesture_features/domain/services/appearance_signature_extractor.dart';
import 'package:gesture_detector/hand_gesture_features/domain/services/yolo_camera_frame_encoder.dart';
import 'package:hand_detection/hand_detection.dart';

void main() {
  const encoder = YoloCameraFrameEncoder(maxDimension: 640, jpegQuality: 90);

  test('keeps raw dimensions when no frame rotation is required', () {
    final encoded = encoder.encode(
      frame: CameraPixelFrameData(
        width: 3,
        height: 2,
        format: CameraPixelFormat.bgra8888,
        planes: [
          CameraPixelPlaneData(
            bytes: Uint8List.fromList(List<int>.filled(3 * 2 * 4, 128)),
            bytesPerRow: 12,
            bytesPerPixel: 4,
          ),
        ],
      ),
      rotation: null,
    );

    expect(encoded, isNotNull);
    expect(encoded!.imageSize, const Size(3, 2));
  });

  test('encodes BGRA with row padding and rotates to upright dimensions', () {
    final encoded = encoder.encode(
      frame: CameraPixelFrameData(
        width: 4,
        height: 2,
        format: CameraPixelFormat.bgra8888,
        planes: [
          CameraPixelPlaneData(
            bytes: Uint8List.fromList([
              0,
              0,
              255,
              255,
              0,
              255,
              0,
              255,
              255,
              0,
              0,
              255,
              255,
              255,
              255,
              255,
              9,
              9,
              9,
              9,
              0,
              0,
              255,
              255,
              0,
              255,
              0,
              255,
              255,
              0,
              0,
              255,
              255,
              255,
              255,
              255,
              9,
              9,
              9,
              9,
            ]),
            bytesPerRow: 20,
            bytesPerPixel: 4,
          ),
        ],
      ),
      rotation: CameraFrameRotation.cw90,
    );

    expect(encoded, isNotNull);
    expect(encoded!.imageSize, const Size(2, 4));
    expect(encoded.jpegBytes, isNotEmpty);
    expect(encoded.jpegBytes.take(2), [0xff, 0xd8]);
  });

  test('encodes Android three-plane YUV420 with chroma strides', () {
    final encoded = encoder.encode(
      frame: CameraPixelFrameData(
        width: 4,
        height: 4,
        format: CameraPixelFormat.yuv420,
        planes: [
          CameraPixelPlaneData(
            bytes: Uint8List.fromList([
              128,
              128,
              128,
              128,
              0,
              0,
              128,
              128,
              128,
              128,
              0,
              0,
              128,
              128,
              128,
              128,
              0,
              0,
              128,
              128,
              128,
              128,
              0,
              0,
            ]),
            bytesPerRow: 6,
            bytesPerPixel: 1,
          ),
          CameraPixelPlaneData(
            bytes: Uint8List.fromList([128, 0, 128, 0, 128, 0, 128, 0]),
            bytesPerRow: 4,
            bytesPerPixel: 2,
          ),
          CameraPixelPlaneData(
            bytes: Uint8List.fromList([128, 0, 128, 0, 128, 0, 128, 0]),
            bytesPerRow: 4,
            bytesPerPixel: 2,
          ),
        ],
      ),
      rotation: CameraFrameRotation.cw180,
    );

    expect(encoded, isNotNull);
    expect(encoded!.imageSize, const Size(4, 4));
    expect(encoded.jpegBytes, isNotEmpty);
  });

  test('encodes single-plane NV21 and resizes before JPEG encoding', () {
    final bytes = Uint8List(8 * 4 + 8 * 2);
    bytes.fillRange(0, 32, 128);
    bytes.fillRange(32, bytes.length, 128);
    const smallEncoder = YoloCameraFrameEncoder(
      maxDimension: 4,
      jpegQuality: 90,
    );
    final encoded = smallEncoder.encode(
      frame: CameraPixelFrameData(
        width: 8,
        height: 4,
        format: CameraPixelFormat.nv21,
        planes: [
          CameraPixelPlaneData(bytes: bytes, bytesPerRow: 8, bytesPerPixel: 1),
        ],
      ),
      rotation: CameraFrameRotation.cw270,
    );

    expect(encoded, isNotNull);
    expect(encoded!.imageSize, const Size(2, 4));
    expect(encoded.jpegBytes, isNotEmpty);
  });

  test('encodes on a background isolate', () async {
    final encoded = await encoder.encodeInBackground(
      frame: CameraPixelFrameData(
        width: 3,
        height: 2,
        format: CameraPixelFormat.bgra8888,
        planes: [
          CameraPixelPlaneData(
            bytes: Uint8List.fromList(List<int>.filled(3 * 2 * 4, 128)),
            bytesPerRow: 12,
            bytesPerPixel: 4,
          ),
        ],
      ),
      rotation: CameraFrameRotation.cw90,
    );

    expect(encoded, isNotNull);
    expect(encoded!.imageSize, const Size(2, 3));
    expect(encoded.jpegBytes.take(2), [0xff, 0xd8]);
  });
}
