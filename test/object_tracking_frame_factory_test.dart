import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:camera_platform_interface/camera_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gesture_detector/hand_gesture_features/domain/services/object_optical_flow_tracker.dart';

void main() {
  const factory = ObjectTrackingFrameFactory();

  test('extracts Android luminance while respecting row stride', () {
    final image = CameraImage.fromPlatformInterface(
      CameraImageData(
        format: const CameraImageFormat(ImageFormatGroup.yuv420, raw: 35),
        height: 2,
        width: 3,
        planes: [
          CameraImagePlane(
            bytes: Uint8List.fromList([10, 20, 30, 0, 40, 50, 60, 0]),
            bytesPerPixel: 1,
            bytesPerRow: 4,
            height: 2,
            width: 3,
          ),
        ],
      ),
    );

    final frame = factory.create(
      image: image,
      frameId: 1,
      capturedAt: DateTime(2026),
      rotation: null,
      mirrorHorizontally: false,
      isBgra: false,
    );

    expect(frame.width, 3);
    expect(frame.height, 2);
    expect(frame.grayscaleBytes, [10, 20, 30, 40, 50, 60]);
  });

  test('converts iOS BGRA pixels to grayscale', () {
    final image = CameraImage.fromPlatformInterface(
      CameraImageData(
        format: const CameraImageFormat(
          ImageFormatGroup.bgra8888,
          raw: 1111970369,
        ),
        height: 1,
        width: 2,
        planes: [
          CameraImagePlane(
            bytes: Uint8List.fromList([0, 0, 255, 255, 255, 0, 0, 255]),
            bytesPerPixel: 4,
            bytesPerRow: 8,
            height: 1,
            width: 2,
          ),
        ],
      ),
    );

    final frame = factory.create(
      image: image,
      frameId: 2,
      capturedAt: DateTime(2026),
      rotation: null,
      mirrorHorizontally: true,
      isBgra: true,
    );

    expect(frame.grayscaleBytes[0], closeTo(76, 1));
    expect(frame.grayscaleBytes[1], closeTo(29, 1));
    expect(frame.mirrorHorizontally, isTrue);
  });
}
