import 'dart:async';

import 'package:camera/camera.dart';
import 'package:camera_platform_interface/camera_platform_interface.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gesture_detector/hand_gesture_features/domain/constants/hand_gesture_thresholds.dart';
import 'package:gesture_detector/hand_gesture_features/domain/models/app_object_detection.dart';
import 'package:gesture_detector/hand_gesture_features/domain/services/native_method_channel_object_detection_service.dart';
import 'package:native_object_detection/native_object_detection.dart';
import 'package:object_detection/object_detection.dart' as od;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel(NativeObjectDetection.channelName);
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  tearDown(() async {
    messenger.setMockMethodCallHandler(channel, null);
  });

  test('serializes camera planes and maps one native detection', () async {
    final calls = <MethodCall>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      if (call.method == 'initialize') {
        final arguments = call.arguments as Map<Object?, Object?>;
        expect(
          arguments['modelAsset'],
          HandGestureThresholds.nativeMethodChannelModelAsset,
        );
        expect(
          arguments['expectedClassCount'],
          HandGestureThresholds.nativeMethodChannelExpectedClassCount,
        );
        expect(
          arguments['confidenceThreshold'],
          HandGestureThresholds.nativeMethodChannelConfidenceThreshold,
        );
        return {'initialized': true, 'accelerator': 'CPU'};
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
        final planes = arguments['planes'] as List<Object?>;
        expect(planes, hasLength(3));
        expect(
          (planes.first as Map<Object?, Object?>)['bytes'],
          isA<Uint8List>(),
        );
        return {
          'frameId': arguments['frameId'],
          'imageWidth': 2,
          'imageHeight': 4,
          'rotationDegrees': 90,
          'cameraFacing': 'front',
          'coordinateSpace': 'upright_unmirrored',
          'detections': [
            {
              'left': 0.25,
              'top': 0.25,
              'right': 0.75,
              'bottom': 0.75,
              'label': 'bottle',
              'classIndex': 39,
              'confidence': 0.91,
              'trackingId': null,
            },
          ],
        };
      }
      if (call.method == 'dispose') return {'disposed': true};
      fail('Unexpected channel method ${call.method}.');
    });

    final service = await NativeMethodChannelObjectDetectionService.start(
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
    expect(
      detections.single.source,
      AppObjectDetectionSource.nativeMethodChannel,
    );
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

    final service = await NativeMethodChannelObjectDetectionService.start(
      isAndroid: true,
    );
    expect(await service.detect(_cameraImage()), isEmpty);
    await service.close();
  });

  test(
    'reports the Android-only boundary before opening the channel',
    () async {
      await expectLater(
        NativeMethodChannelObjectDetectionService.start(isAndroid: false),
        throwsA(isA<UnsupportedError>()),
      );
    },
  );

  test('rejects a second request while native inference is active', () async {
    final nativeDetector = _BlockingNativeDetector();
    final service = await NativeMethodChannelObjectDetectionService.start(
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

    final service = await NativeMethodChannelObjectDetectionService.start(
      isAndroid: true,
    );
    expect(await service.detect(_cameraImage()), isEmpty);
    await service.close();
  });
}

final class _BlockingNativeDetector extends NativeObjectDetection {
  _BlockingNativeDetector();

  final started = Completer<void>();
  final release = Completer<void>();

  @override
  Future<Map<Object?, Object?>> initialize({
    required String modelAsset,
    required double confidenceThreshold,
    required double iouThreshold,
    required int maxResults,
    required int expectedClassCount,
    required bool useGpu,
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
