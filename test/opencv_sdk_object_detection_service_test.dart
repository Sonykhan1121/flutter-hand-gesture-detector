import 'dart:async';
import 'package:camera/camera.dart';
import 'package:camera_platform_interface/camera_platform_interface.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gesture_detector/hand_gesture_features/domain/constants/hand_gesture_thresholds.dart';
import 'package:gesture_detector/hand_gesture_features/domain/models/app_object_detection.dart';
import 'package:gesture_detector/hand_gesture_features/domain/services/opencv_sdk_object_detection_service.dart';
import 'package:object_detection/object_detection.dart' as od;
import 'package:opencv_object_detection/opencv_object_detection.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel(OpenCvObjectDetection.channelName);
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  tearDown(() async {
    messenger.setMockMethodCallHandler(channel, null);
  });

  test('serializes camera planes and maps one OpenCV detection', () async {
    final calls = <MethodCall>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      if (call.method == 'initialize') {
        final arguments = call.arguments as Map<Object?, Object?>;
        expect(
          arguments['modelAsset'],
          HandGestureThresholds.opencvSdkModelAsset,
        );
        expect(
          arguments['metadataAsset'],
          HandGestureThresholds.opencvSdkMetadataAsset,
        );
        expect(
          arguments['expectedClassCount'],
          HandGestureThresholds.opencvSdkExpectedClassCount,
        );
        expect(
          arguments['confidenceThreshold'],
          HandGestureThresholds.opencvSdkConfidenceThreshold,
        );
        expect(arguments.containsKey('useGpu'), isFalse);
        return {'initialized': true, 'target': 'CPU'};
      }
      if (call.method == 'getCapabilities') {
        return {'platform': 'android', 'initialized': true};
      }
      if (call.method == 'detect') {
        final arguments = call.arguments as Map<Object?, Object?>;
        expect(arguments['width'], 4);
        expect(arguments['height'], 2);
        expect(arguments['format'], 'yuv420');
        expect(arguments['rotationDegrees'], 90);
        expect(arguments['cameraFacing'], 'front');
        expect(arguments['planes'], hasLength(3));
        return {
          'frameId': arguments['frameId'],
          'imageWidth': 2,
          'imageHeight': 4,
          'rotationDegrees': 90,
          'cameraFacing': 'front',
          'coordinateSpace': 'upright_unmirrored',
          'preprocessMs': 3.0,
          'inferenceMs': 20.0,
          'postprocessMs': 2.0,
          'detections': [
            {
              'left': 0.25,
              'top': 0.25,
              'right': 0.75,
              'bottom': 0.75,
              'label': 'Bottle',
              'classIndex': 57,
              'confidence': 0.91,
              'trackingId': null,
            },
          ],
        };
      }
      if (call.method == 'dispose') return {'disposed': true};
      fail('Unexpected channel method ${call.method}.');
    });

    final service = await OpenCvSdkObjectDetectionService.start(
      isAndroid: true,
    );
    final detections = await service.detect(
      _cameraImage(),
      rotation: od.CameraFrameRotation.cw90,
      lensDirection: CameraLensDirection.front,
    );

    expect(detections, hasLength(1));
    expect(detections.single.boundingBox.left, 0.5);
    expect(detections.single.boundingBox.top, 1);
    expect(detections.single.source, AppObjectDetectionSource.opencvSdk);
    expect(calls.map((call) => call.method), [
      'initialize',
      'getCapabilities',
      'detect',
    ]);

    await service.close();
    expect(calls.last.method, 'dispose');
  });

  test('ignores a response carrying the wrong frame ID', () async {
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'initialize' || call.method == 'getCapabilities') {
        return {'initialized': true};
      }
      if (call.method == 'detect') {
        return {
          'frameId': 999,
          'imageWidth': 4,
          'imageHeight': 2,
          'rotationDegrees': 0,
          'cameraFacing': 'unknown',
          'coordinateSpace': 'upright_unmirrored',
          'detections': const [],
        };
      }
      return null;
    });

    final service = await OpenCvSdkObjectDetectionService.start(
      isAndroid: true,
    );
    expect(await service.detect(_cameraImage()), isEmpty);
    await service.close();
  });

  test(
    'reports the Android-only boundary before opening the channel',
    () async {
      await expectLater(
        OpenCvSdkObjectDetectionService.start(isAndroid: false),
        throwsA(isA<UnsupportedError>()),
      );
    },
  );

  test('rejects a second request while OpenCV inference is active', () async {
    final nativeDetector = _BlockingOpenCvDetector();
    final service = await OpenCvSdkObjectDetectionService.start(
      nativeDetector: nativeDetector,
      isAndroid: true,
    );

    final first = service.detect(_cameraImage());
    await nativeDetector.started.future;
    await expectLater(
      service.detect(_cameraImage()),
      throwsA(isA<StateError>()),
    );

    nativeDetector.release.complete();
    expect(await first, isEmpty);
    await service.close();
  });

  test('rejects a response with a mismatched coordinate contract', () async {
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'initialize' || call.method == 'getCapabilities') {
        return {'initialized': true};
      }
      if (call.method == 'detect') {
        final frame = call.arguments as Map<Object?, Object?>;
        return {
          'frameId': frame['frameId'],
          'imageWidth': 4,
          'imageHeight': 2,
          'rotationDegrees': 90,
          'cameraFacing': 'back',
          'coordinateSpace': 'raw_mirrored',
          'detections': const [],
        };
      }
      return null;
    });

    final service = await OpenCvSdkObjectDetectionService.start(
      isAndroid: true,
    );
    expect(await service.detect(_cameraImage()), isEmpty);
    await service.close();
  });
}

final class _BlockingOpenCvDetector extends OpenCvObjectDetection {
  _BlockingOpenCvDetector();

  final started = Completer<void>();
  final release = Completer<void>();

  @override
  Future<Map<Object?, Object?>> initialize({
    required String modelAsset,
    required String metadataAsset,
    required double confidenceThreshold,
    required double iouThreshold,
    required int maxResults,
    required int expectedClassCount,
  }) async => const {'initialized': true};

  @override
  Future<Map<Object?, Object?>> getCapabilities() async => const {
    'platform': 'android',
    'initialized': true,
  };

  @override
  Future<Map<Object?, Object?>> detect(Map<String, Object?> frame) async {
    started.complete();
    await release.future;
    return {
      'frameId': frame['frameId'],
      'imageWidth': frame['width'],
      'imageHeight': frame['height'],
      'rotationDegrees': frame['rotationDegrees'],
      'cameraFacing': frame['cameraFacing'],
      'coordinateSpace': 'upright_unmirrored',
      'detections': const [],
    };
  }

  @override
  Future<void> dispose() async {}
}

CameraImage _cameraImage() {
  return CameraImage.fromPlatformInterface(
    CameraImageData(
      format: const CameraImageFormat(ImageFormatGroup.yuv420, raw: 35),
      height: 2,
      width: 4,
      planes: [
        CameraImagePlane(
          bytes: Uint8List.fromList(List<int>.filled(8, 128)),
          bytesPerPixel: 1,
          bytesPerRow: 4,
          height: 2,
          width: 4,
        ),
        CameraImagePlane(
          bytes: Uint8List.fromList([128, 128]),
          bytesPerPixel: 1,
          bytesPerRow: 2,
          height: 1,
          width: 2,
        ),
        CameraImagePlane(
          bytes: Uint8List.fromList([128, 128]),
          bytesPerPixel: 1,
          bytesPerRow: 2,
          height: 1,
          width: 2,
        ),
      ],
    ),
  );
}
