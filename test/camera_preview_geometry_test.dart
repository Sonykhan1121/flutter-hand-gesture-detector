import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:gesture_detector/hand_gesture_features/domain/utils/camera_preview_geometry.dart';

void main() {
  group('orientedCameraPreviewSize', () {
    test('uses 9:16 ordering in portrait', () {
      final size = orientedCameraPreviewSize(
        rawPreviewSize: const Size(1920, 1080),
        isLandscape: false,
      );

      expect(size, const Size(1080, 1920));
      expect(size.width / size.height, closeTo(9 / 16, 0.0001));
    });

    test('uses 16:9 ordering in landscape', () {
      final size = orientedCameraPreviewSize(
        rawPreviewSize: const Size(1080, 1920),
        isLandscape: true,
      );

      expect(size, const Size(1920, 1080));
      expect(size.width / size.height, closeTo(16 / 9, 0.0001));
    });

    test('falls back safely when the controller has no preview size', () {
      expect(
        orientedCameraPreviewSize(rawPreviewSize: null, isLandscape: false),
        const Size(9, 16),
      );
      expect(
        orientedCameraPreviewSize(rawPreviewSize: Size.zero, isLandscape: true),
        const Size(16, 9),
      );
    });
  });

  group('normalizedDisplayRectToCanvasRect', () {
    const box = Rect.fromLTRB(0.10, 0.20, 0.40, 0.60);

    test('maps the same normalized box onto a portrait painter canvas', () {
      final rect = normalizedDisplayRectToCanvasRect(
        box,
        const Size(900, 1600),
      );

      expect(rect, const Rect.fromLTRB(90, 320, 360, 960));
    });

    test('maps the same normalized box onto a landscape painter canvas', () {
      final rect = normalizedDisplayRectToCanvasRect(
        box,
        const Size(1600, 900),
      );

      expect(rect, const Rect.fromLTRB(160, 180, 640, 540));
    });

    test('clamps boxes to the visible preview', () {
      final rect = normalizedDisplayRectToCanvasRect(
        const Rect.fromLTRB(-0.2, -0.1, 1.2, 1.1),
        const Size(1600, 900),
      );

      expect(rect, const Rect.fromLTRB(0, 0, 1600, 900));
    });

    test('rotates a normalized box clockwise for landscape preview', () {
      final rect = normalizedDisplayRectToCanvasRect(
        box,
        const Size(1600, 900),
        previewQuarterTurns: 1,
      );

      expect(rect, const Rect.fromLTRB(640, 90, 1280, 360));
    });
  });

  group('camera-only transition geometry', () {
    const viewport = Size(400, 800);
    const rawPreview = Size(1920, 1080);

    test('fits portrait, midpoint, and landscape cards in one upright UI', () {
      final portrait = interpolatedCameraPreviewSize(
        viewportSize: viewport,
        rawPreviewSize: rawPreview,
        progress: 0,
      );
      final midpoint = interpolatedCameraPreviewSize(
        viewportSize: viewport,
        rawPreviewSize: rawPreview,
        progress: 0.5,
      );
      final landscape = interpolatedCameraPreviewSize(
        viewportSize: viewport,
        rawPreviewSize: rawPreview,
        progress: 1,
      );

      expect(portrait, const Size(400, 711.1111111111111));
      expect(midpoint.width, 400);
      expect(midpoint.height, closeTo(468.0556, 0.001));
      expect(landscape, const Size(400, 225));
    });

    test('hides overlays exactly when their mapping switches', () {
      expect(cameraOverlayOpacity(0), 1);
      expect(cameraOverlayOpacity(0.25), 0.5);
      expect(cameraOverlayOpacity(0.5), 0);
      expect(cameraOverlayOpacity(0.75), 0.5);
      expect(cameraOverlayOpacity(1), 1);
      expect(cameraPreviewQuarterTurns(0.499), 0);
      expect(cameraPreviewQuarterTurns(0.5), 1);
    });

    test('corrects only the Android recording preview counterclockwise', () {
      expect(
        recordingCameraPreviewQuarterTurns(
          isAndroid: true,
          isRecordingPreview: true,
        ),
        3,
      );
      expect(
        recordingCameraPreviewQuarterTurns(
          isAndroid: true,
          isRecordingPreview: false,
        ),
        0,
      );
      expect(
        recordingCameraPreviewQuarterTurns(
          isAndroid: false,
          isRecordingPreview: true,
        ),
        0,
      );
    });

    test('mirrors a front-camera point before rotating it clockwise', () {
      const detectorPoint = Offset(0.2, 0.3);
      const mirroredPoint = Offset(0.8, 0.3);

      expect(
        rotateNormalizedDisplayPoint(mirroredPoint, 1),
        const Offset(0.7, 0.8),
      );
      expect(detectorPoint, const Offset(0.2, 0.3));
    });
  });

  group('detectionPointToPreviewCanvas', () {
    test('maps normal, mirrored, and rotated preview coordinates', () {
      expect(
        detectionPointToPreviewCanvas(
          sourcePoint: const Offset(20, 30),
          detectionImageSize: const Size(100, 100),
          canvasSize: const Size(300, 500),
          mirrorHorizontally: false,
          previewQuarterTurns: 0,
          useRecordingPreviewMapping: false,
        ),
        const Offset(60, 150),
      );
      expect(
        detectionPointToPreviewCanvas(
          sourcePoint: const Offset(20, 30),
          detectionImageSize: const Size(100, 100),
          canvasSize: const Size(300, 500),
          mirrorHorizontally: true,
          previewQuarterTurns: 1,
          useRecordingPreviewMapping: false,
        ),
        const Offset(210, 400),
      );
    });

    test('uses rotate then mirror and cover-fit for recording preview', () {
      final point = detectionPointToPreviewCanvas(
        sourcePoint: const Offset(20, 30),
        detectionImageSize: const Size(100, 200),
        canvasSize: const Size(400, 200),
        mirrorHorizontally: true,
        previewQuarterTurns: 1,
        useRecordingPreviewMapping: true,
      );

      expect(point?.dx, closeTo(60, 0.000001));
      expect(point?.dy, closeTo(40, 0.000001));
    });

    test('fails closed for invalid source or canvas geometry', () {
      expect(
        detectionPointToPreviewCanvas(
          sourcePoint: const Offset(double.nan, 10),
          detectionImageSize: const Size(100, 100),
          canvasSize: const Size(300, 500),
          mirrorHorizontally: false,
          previewQuarterTurns: 0,
          useRecordingPreviewMapping: false,
        ),
        isNull,
      );
      expect(
        detectionPointToPreviewCanvas(
          sourcePoint: const Offset(10, 10),
          detectionImageSize: Size.zero,
          canvasSize: const Size(300, 500),
          mirrorHorizontally: false,
          previewQuarterTurns: 0,
          useRecordingPreviewMapping: false,
        ),
        isNull,
      );
    });
  });
}
