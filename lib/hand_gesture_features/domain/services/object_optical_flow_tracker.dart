import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

import 'package:camera/camera.dart';
import 'package:hand_detection/hand_detection.dart';
import 'package:opencv_dart/opencv_dart.dart' as cv;

import '../constants/hand_gesture_thresholds.dart';
import '../models/object_optical_flow_track_result.dart';
import '../models/object_tracking_frame.dart';
import '../utils/camera_frame_box_mapper.dart';

/// Builds compact grayscale frames without decoding the full camera image.
class ObjectTrackingFrameFactory {
  const ObjectTrackingFrameFactory();

  ObjectTrackingFrame create({
    required CameraImage image,
    required int frameId,
    required DateTime capturedAt,
    required CameraFrameRotation? rotation,
    required bool mirrorHorizontally,
    required bool isBgra,
    int maxDimension = HandGestureThresholds.objectTrackingMaxDimension,
    bool useFastBgraLuma = false,
  }) {
    final boundedMaxDimension = math.max(1, maxDimension);
    final scale = math.min(
      1.0,
      boundedMaxDimension / math.max(image.width, image.height),
    );
    final width = math.max(1, (image.width * scale).round());
    final height = math.max(1, (image.height * scale).round());
    final output = Uint8List(width * height);
    final plane = image.planes.first;

    for (var y = 0; y < height; y++) {
      final sourceY = math.min(image.height - 1, (y / scale).floor());
      for (var x = 0; x < width; x++) {
        final sourceX = math.min(image.width - 1, (x / scale).floor());
        if (isBgra) {
          final pixelStride = plane.bytesPerPixel ?? 4;
          final index = sourceY * plane.bytesPerRow + sourceX * pixelStride;
          if (index + 2 < plane.bytes.length) {
            if (useFastBgraLuma) {
              // Green is a stable, inexpensive luminance proxy for optical
              // flow. iOS uses this path to avoid three-channel floating-point
              // conversion on the Flutter UI isolate for every camera frame.
              output[y * width + x] = plane.bytes[index + 1];
            } else {
              final blue = plane.bytes[index];
              final green = plane.bytes[index + 1];
              final red = plane.bytes[index + 2];
              output[y * width + x] = (0.114 * blue +
                      0.587 * green +
                      0.299 * red)
                  .round()
                  .clamp(0, 255);
            }
          }
        } else {
          final pixelStride = plane.bytesPerPixel ?? 1;
          final index = sourceY * plane.bytesPerRow + sourceX * pixelStride;
          if (index < plane.bytes.length) {
            output[y * width + x] = plane.bytes[index];
          }
        }
      }
    }

    return ObjectTrackingFrame(
      frameId: frameId,
      capturedAt: capturedAt,
      width: width,
      height: height,
      grayscaleBytes: output,
      rotation: rotation,
      mirrorHorizontally: mirrorHorizontally,
    );
  }
}

/// Tracks one selected object between slower detector cycles.
class ObjectOpticalFlowTracker {
  cv.Mat? _previousGray;
  cv.VecPoint2f? _previousPoints;
  Rect? _rawFrameBox;
  ObjectOpticalFlowTrackResult? _lastResult;
  DateTime? _lastFilterAt;
  int _trackedFramesSinceSeed = 0;
  final List<_TrackingHistoryEntry> _history = [];
  final List<_OneEuroFilter> _boxFilters = List.generate(
    4,
    (_) => _OneEuroFilter(
      minCutoff: HandGestureThresholds.objectTrackingOneEuroMinCutoff,
      beta: HandGestureThresholds.objectTrackingOneEuroBeta,
      derivativeCutoff:
          HandGestureThresholds.objectTrackingOneEuroDerivativeCutoff,
    ),
  );

  bool get isActive =>
      _previousGray != null && _previousPoints != null && _rawFrameBox != null;

  ObjectOpticalFlowTrackResult? get lastResult => _lastResult;

  Rect? displayBoxForFrame(int frameId) {
    for (final entry in _history.reversed) {
      if (entry.frame.frameId == frameId) return entry.displayBox;
    }
    return null;
  }

  ObjectOpticalFlowTrackResult seed(
    ObjectTrackingFrame frame,
    Rect displayBox, {
    bool resetSmoothing = true,
  }) {
    _resetActive();
    if (resetSmoothing) _resetFilters();

    final rawBox = displayRectToCameraFrameRect(
      displayRect: displayBox,
      rotation: frame.rotation,
      mirrorHorizontally: frame.mirrorHorizontally,
    );
    final gray = _matFor(frame);
    final points = _featuresInside(gray, rawBox);
    if (points.length < HandGestureThresholds.objectTrackingMinFeatures) {
      final pointCount = points.length;
      gray.dispose();
      points.dispose();
      return _uncertain(
        frame: frame,
        displayBox: displayBox,
        validPoints: pointCount,
        reason: 'not enough object features',
      );
    }

    _previousGray = gray;
    _previousPoints = points;
    _rawFrameBox = rawBox;
    _trackedFramesSinceSeed = 0;
    final smoothed = _smooth(displayBox, frame.capturedAt);
    final result = ObjectOpticalFlowTrackResult(
      status: ObjectOpticalFlowTrackStatus.initialized,
      frameId: frame.frameId,
      displayBox: smoothed,
      rawDisplayBox: displayBox,
      confidence: 1,
      validPointCount: points.length,
      inlierRatio: 1,
      featurePoints: _displayPoints(points, frame),
    );
    _lastResult = result;
    _remember(frame, smoothed);
    return result;
  }

  ObjectOpticalFlowTrackResult update(ObjectTrackingFrame frame) {
    final previousGray = _previousGray;
    final previousPoints = _previousPoints;
    final previousRawBox = _rawFrameBox;
    final fallbackBox = _lastResult?.displayBox ?? Rect.zero;
    if (previousGray == null ||
        previousPoints == null ||
        previousRawBox == null) {
      return _uncertain(
        frame: frame,
        displayBox: fallbackBox,
        reason: 'tracker is not initialized',
      );
    }

    final nextGray = _matFor(frame);
    final forward = _bestTemplateMatch(
      source: previousGray,
      destination: nextGray,
      sourceBox: previousRawBox,
    );
    if (forward == null) {
      return _failAndRelease(
        frame: frame,
        nextGray: nextGray,
        displayBox: fallbackBox,
        reason: 'forward frame match failed',
      );
    }
    final backward = _bestTemplateMatch(
      source: nextGray,
      destination: previousGray,
      sourceBox: forward.rawBox,
    );
    if (backward == null) {
      return _failAndRelease(
        frame: frame,
        nextGray: nextGray,
        displayBox: fallbackBox,
        reason: 'backward frame match failed',
      );
    }

    final similarity = math.min(forward.score, backward.score);
    final backwardError =
        (backward.rawBox.center - previousRawBox.center).distance *
        math.max(frame.width, frame.height);
    final scale = forward.rawBox.width / previousRawBox.width;
    final centerJump = (forward.rawBox.center - previousRawBox.center).distance;
    if (similarity < HandGestureThresholds.objectTrackingMinInlierRatio ||
        backwardError >
            HandGestureThresholds.objectTrackingForwardBackwardError ||
        scale < HandGestureThresholds.objectTrackingMinFrameScale ||
        scale > HandGestureThresholds.objectTrackingMaxFrameScale ||
        centerJump > HandGestureThresholds.objectTrackingMaxCenterJump) {
      return _failAndRelease(
        frame: frame,
        nextGray: nextGray,
        displayBox: fallbackBox,
        validPoints: previousPoints.length,
        inlierRatio: similarity,
        reason:
            'unsafe forward/backward frame match '
            'forward=${forward.score.toStringAsFixed(3)} '
            'backward=${backward.score.toStringAsFixed(3)} '
            'error=${backwardError.toStringAsFixed(2)} '
            'box=${forward.rawBox}',
      );
    }

    final transformedRawBox = forward.rawBox;
    var nextStatePoints = _transformFeaturePoints(
      previousPoints,
      from: previousRawBox,
      to: transformedRawBox,
      size: frame.size,
    );

    _trackedFramesSinceSeed++;
    if (nextStatePoints.length <
            HandGestureThresholds.objectTrackingReseedFeatureCount ||
        _trackedFramesSinceSeed >=
            HandGestureThresholds.objectTrackingReseedFrameCount) {
      nextStatePoints.dispose();
      nextStatePoints = _featuresInside(nextGray, transformedRawBox);
      _trackedFramesSinceSeed = 0;
    }

    final rawDisplayBox = _displayBox(transformedRawBox, frame);
    final smoothed = _smooth(rawDisplayBox, frame.capturedAt);
    final confidence = similarity.clamp(0.0, 1.0);

    previousGray.dispose();
    previousPoints.dispose();
    _previousGray = nextGray;
    _previousPoints = nextStatePoints;
    _rawFrameBox = transformedRawBox;

    final result = ObjectOpticalFlowTrackResult(
      status: ObjectOpticalFlowTrackStatus.tracked,
      frameId: frame.frameId,
      displayBox: smoothed,
      rawDisplayBox: rawDisplayBox,
      confidence: confidence,
      validPointCount: nextStatePoints.length,
      inlierRatio: similarity,
      featurePoints: _displayPoints(nextStatePoints, frame),
    );
    _lastResult = result;
    _remember(frame, smoothed);
    return result;
  }

  /// Applies a delayed detector correction to the latest tracked box.
  ObjectOpticalFlowTrackResult? correctFromDetection({
    required ObjectTrackingFrame currentFrame,
    required int detectedFrameId,
    required Rect detectedDisplayBox,
  }) {
    final historical = displayBoxForFrame(detectedFrameId);
    final current = _lastResult?.displayBox;
    if (historical == null || current == null || historical.isEmpty) {
      return null;
    }

    final blend = HandGestureThresholds.objectTrackingCorrectionBlend;
    final delta = detectedDisplayBox.center - historical.center;
    final widthRatio = (detectedDisplayBox.width / historical.width).clamp(
      0.70,
      1.40,
    );
    final heightRatio = (detectedDisplayBox.height / historical.height).clamp(
      0.70,
      1.40,
    );
    final center = current.center + delta * blend;
    final width = current.width * (1 + (widthRatio - 1) * blend);
    final height = current.height * (1 + (heightRatio - 1) * blend);
    final corrected = _clampDisplayRect(
      Rect.fromCenter(center: center, width: width, height: height),
    );
    return seed(currentFrame, corrected, resetSmoothing: false);
  }

  void reset() {
    _resetActive();
    _history.clear();
    _lastResult = null;
    _resetFilters();
  }

  void dispose() => reset();

  cv.Mat _matFor(ObjectTrackingFrame frame) => cv.Mat.fromList(
    frame.height,
    frame.width,
    cv.MatType.CV_8UC1,
    frame.grayscaleBytes,
  );

  cv.VecPoint2f _featuresInside(cv.Mat gray, Rect rawBox) {
    final central = Rect.fromCenter(
      center: rawBox.center,
      width: rawBox.width * 0.80,
      height: rawBox.height * 0.80,
    );
    final maskBytes = Uint8List(gray.rows * gray.cols);
    final left = (central.left * gray.cols).floor().clamp(0, gray.cols - 1);
    final top = (central.top * gray.rows).floor().clamp(0, gray.rows - 1);
    final right = (central.right * gray.cols).ceil().clamp(left + 1, gray.cols);
    final bottom = (central.bottom * gray.rows).ceil().clamp(
      top + 1,
      gray.rows,
    );
    for (var y = top; y < bottom; y++) {
      maskBytes.fillRange(y * gray.cols + left, y * gray.cols + right, 255);
    }
    final mask = cv.Mat.fromList(
      gray.rows,
      gray.cols,
      cv.MatType.CV_8UC1,
      maskBytes,
    );
    try {
      return cv.goodFeaturesToTrack(
        gray,
        HandGestureThresholds.objectTrackingMaxFeatures,
        HandGestureThresholds.objectTrackingFeatureQuality,
        HandGestureThresholds.objectTrackingFeatureMinDistance,
        mask: mask,
      );
    } finally {
      mask.dispose();
    }
  }

  _TemplateMatch? _bestTemplateMatch({
    required cv.Mat source,
    required cv.Mat destination,
    required Rect sourceBox,
  }) {
    final templateBox = Rect.fromCenter(
      center: sourceBox.center,
      width: sourceBox.width * 0.80,
      height: sourceBox.height * 0.80,
    );
    final sourcePixels = _pixelRect(templateBox, source.cols, source.rows);
    if (sourcePixels.width < 8 || sourcePixels.height < 8) return null;

    final horizontalPadding = math.max(sourceBox.width * 0.75, 0.08);
    final verticalPadding = math.max(sourceBox.height * 0.75, 0.08);
    final searchBox = Rect.fromLTRB(
      (sourceBox.left - horizontalPadding).clamp(0.0, 1.0),
      (sourceBox.top - verticalPadding).clamp(0.0, 1.0),
      (sourceBox.right + horizontalPadding).clamp(0.0, 1.0),
      (sourceBox.bottom + verticalPadding).clamp(0.0, 1.0),
    );
    final searchPixels = _pixelRect(
      searchBox,
      destination.cols,
      destination.rows,
    );
    final sourceRoi = cv.Rect(
      sourcePixels.x,
      sourcePixels.y,
      sourcePixels.width,
      sourcePixels.height,
    );
    final searchRoi = cv.Rect(
      searchPixels.x,
      searchPixels.y,
      searchPixels.width,
      searchPixels.height,
    );
    final template = cv.Mat.fromMat(source, roi: sourceRoi, copy: true);
    final search = cv.Mat.fromMat(destination, roi: searchRoi, copy: true);
    sourceRoi.dispose();
    searchRoi.dispose();
    _TemplateMatch? best;
    try {
      // Detector corrections handle gradual scale changes. Frame-to-frame
      // tracking intentionally keeps size stable to avoid high-correlation
      // matches against a small subregion of the selected object.
      for (final scale in const [1.0]) {
        final width = math.max(8, (template.cols * scale).round());
        final height = math.max(8, (template.rows * scale).round());
        if (width > search.cols || height > search.rows) continue;
        final scaled =
            scale == 1.0
                ? cv.Mat.fromMat(template)
                : cv.resize(template, (width, height));
        final scores = cv.matchTemplate(search, scaled, cv.TM_CCOEFF_NORMED);
        try {
          final extrema = cv.minMaxLoc(scores);
          final maxLocation = extrema.$4;
          final score = extrema.$2;
          final rank = score - math.log(scale).abs() * 0.20;
          final x = searchPixels.x + maxLocation.x;
          final y = searchPixels.y + maxLocation.y;
          extrema.$3.dispose();
          maxLocation.dispose();
          if (!score.isFinite || (best != null && rank <= best.rank)) {
            continue;
          }
          best = _TemplateMatch(
            score: score,
            rank: rank,
            rawBox: Rect.fromCenter(
              center: Offset(
                (x + width / 2) / destination.cols,
                (y + height / 2) / destination.rows,
              ),
              width: sourceBox.width * scale,
              height: sourceBox.height * scale,
            ),
          );
        } finally {
          scores.dispose();
          scaled.dispose();
        }
      }
    } finally {
      template.dispose();
      search.dispose();
    }
    return best;
  }

  cv.VecPoint2f _transformFeaturePoints(
    cv.VecPoint2f points, {
    required Rect from,
    required Rect to,
    required Size size,
  }) {
    final transformed = <cv.Point2f>[];
    for (var index = 0; index < points.length; index++) {
      final point = points[index];
      final normalized = Offset(point.x / size.width, point.y / size.height);
      final relativeX = (normalized.dx - from.left) / from.width;
      final relativeY = (normalized.dy - from.top) / from.height;
      final next = Offset(
        to.left + relativeX * to.width,
        to.top + relativeY * to.height,
      );
      if (next.dx >= 0 && next.dx <= 1 && next.dy >= 0 && next.dy <= 1) {
        transformed.add(
          cv.Point2f(next.dx * size.width, next.dy * size.height),
        );
      }
    }
    final result = cv.VecPoint2f.fromList(transformed);
    for (final point in transformed) {
      point.dispose();
    }
    return result;
  }

  _PixelRect _pixelRect(Rect box, int width, int height) {
    final left = (box.left * width).floor().clamp(0, width - 1);
    final top = (box.top * height).floor().clamp(0, height - 1);
    final right = (box.right * width).ceil().clamp(left + 1, width);
    final bottom = (box.bottom * height).ceil().clamp(top + 1, height);
    return _PixelRect(left, top, right - left, bottom - top);
  }

  Rect _displayBox(Rect rawBox, ObjectTrackingFrame frame) {
    return cameraFrameRectToDisplayBox(
      rect: Rect.fromLTRB(
        rawBox.left * frame.width,
        rawBox.top * frame.height,
        rawBox.right * frame.width,
        rawBox.bottom * frame.height,
      ),
      imageSize: frame.size,
      rotation: frame.rotation,
      mirrorHorizontally: frame.mirrorHorizontally,
    );
  }

  List<Offset> _displayPoints(cv.VecPoint2f points, ObjectTrackingFrame frame) {
    return List<Offset>.generate(points.length, (index) {
      final point = points[index];
      return cameraFramePointToDisplayPoint(
        point: Offset(point.x, point.y),
        imageSize: frame.size,
        rotation: frame.rotation,
        mirrorHorizontally: frame.mirrorHorizontally,
      );
    }, growable: false);
  }

  Rect _smooth(Rect box, DateTime timestamp) {
    final previousAt = _lastFilterAt;
    final elapsed =
        previousAt == null
            ? 1 / 20
            : math.max(
              0.001,
              timestamp.difference(previousAt).inMicroseconds / 1e6,
            );
    _lastFilterAt = timestamp;
    return _clampDisplayRect(
      Rect.fromLTRB(
        _boxFilters[0].filter(box.left, elapsed),
        _boxFilters[1].filter(box.top, elapsed),
        _boxFilters[2].filter(box.right, elapsed),
        _boxFilters[3].filter(box.bottom, elapsed),
      ),
    );
  }

  void _remember(ObjectTrackingFrame frame, Rect displayBox) {
    _history.add(_TrackingHistoryEntry(frame: frame, displayBox: displayBox));
    while (_history.length >
        HandGestureThresholds.objectTrackingHistoryLength) {
      _history.removeAt(0);
    }
  }

  ObjectOpticalFlowTrackResult _failAndRelease({
    required ObjectTrackingFrame frame,
    required cv.Mat nextGray,
    required Rect displayBox,
    required String reason,
    int validPoints = 0,
    double inlierRatio = 0,
  }) {
    nextGray.dispose();
    _resetActive();
    return _uncertain(
      frame: frame,
      displayBox: displayBox,
      validPoints: validPoints,
      inlierRatio: inlierRatio,
      reason: reason,
    );
  }

  ObjectOpticalFlowTrackResult _uncertain({
    required ObjectTrackingFrame frame,
    required Rect displayBox,
    required String reason,
    int validPoints = 0,
    double inlierRatio = 0,
  }) {
    final result = ObjectOpticalFlowTrackResult(
      status: ObjectOpticalFlowTrackStatus.uncertain,
      frameId: frame.frameId,
      displayBox: displayBox,
      rawDisplayBox: displayBox,
      confidence: 0,
      validPointCount: validPoints,
      inlierRatio: inlierRatio,
      featurePoints: const [],
      rejectionReason: reason,
    );
    _lastResult = result;
    return result;
  }

  void _resetActive() {
    _previousGray?.dispose();
    _previousPoints?.dispose();
    _previousGray = null;
    _previousPoints = null;
    _rawFrameBox = null;
    _trackedFramesSinceSeed = 0;
  }

  void _resetFilters() {
    for (final filter in _boxFilters) {
      filter.reset();
    }
    _lastFilterAt = null;
  }

  Rect _clampDisplayRect(Rect box) => Rect.fromLTRB(
    box.left.clamp(0.0, 1.0),
    box.top.clamp(0.0, 1.0),
    box.right.clamp(0.0, 1.0),
    box.bottom.clamp(0.0, 1.0),
  );
}

class _TrackingHistoryEntry {
  const _TrackingHistoryEntry({required this.frame, required this.displayBox});

  final ObjectTrackingFrame frame;
  final Rect displayBox;
}

class _TemplateMatch {
  const _TemplateMatch({
    required this.score,
    required this.rank,
    required this.rawBox,
  });

  final double score;
  final double rank;
  final Rect rawBox;
}

class _PixelRect {
  const _PixelRect(this.x, this.y, this.width, this.height);

  final int x;
  final int y;
  final int width;
  final int height;
}

class _OneEuroFilter {
  _OneEuroFilter({
    required this.minCutoff,
    required this.beta,
    required this.derivativeCutoff,
  });

  final double minCutoff;
  final double beta;
  final double derivativeCutoff;
  double? _value;
  double _derivative = 0;

  double filter(double value, double elapsedSeconds) {
    final previous = _value;
    if (previous == null) {
      _value = value;
      return value;
    }
    final derivative = (value - previous) / elapsedSeconds;
    final derivativeAlpha = _alpha(derivativeCutoff, elapsedSeconds);
    _derivative += derivativeAlpha * (derivative - _derivative);
    final cutoff = minCutoff + beta * _derivative.abs();
    final alpha = _alpha(cutoff, elapsedSeconds);
    final filtered = previous + alpha * (value - previous);
    _value = filtered;
    return filtered;
  }

  double _alpha(double cutoff, double elapsedSeconds) {
    final tau = 1 / (2 * math.pi * cutoff);
    return 1 / (1 + tau / elapsedSeconds);
  }

  void reset() {
    _value = null;
    _derivative = 0;
  }
}
