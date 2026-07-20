import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:hand_detection/hand_detection.dart';

import '../../domain/constants/hand_gesture_thresholds.dart';
import '../../domain/services/hand_geometry_service.dart';

/// Draws the two Zoom In rays, their angle, and accepted intersection.
class ZoomInDebugOverlayPainter extends CustomPainter {
  const ZoomInDebugOverlayPainter({
    required this.hand,
    required this.imageSize,
    required this.mirrorHorizontally,
    this.previewQuarterTurns = 0,
    this.useRecordingPreviewMapping = false,
    this.geometry = const HandGeometryService(),
  });

  final Hand? hand;
  final Size imageSize;
  final bool mirrorHorizontally;
  final int previewQuarterTurns;
  final bool useRecordingPreviewMapping;
  final HandGeometryService geometry;

  @override
  void paint(Canvas canvas, Size size) {
    final currentHand = hand;
    if (currentHand == null ||
        imageSize.width <= 0 ||
        imageSize.height <= 0 ||
        size.width <= 0 ||
        size.height <= 0) {
      return;
    }

    final thumbIp = _visibleLandmark(currentHand, HandLandmarkType.thumbIP);
    final thumbTip = _visibleLandmark(currentHand, HandLandmarkType.thumbTip);
    final indexDip = _visibleLandmark(
      currentHand,
      HandLandmarkType.indexFingerDIP,
    );
    final indexTip = _visibleLandmark(
      currentHand,
      HandLandmarkType.indexFingerTip,
    );
    if (thumbIp == null ||
        thumbTip == null ||
        indexDip == null ||
        indexTip == null) {
      return;
    }

    final angle = geometry.angleBetweenLandmarkSegments2D(
      firstStart: thumbIp,
      firstEnd: thumbTip,
      secondStart: indexDip,
      secondEnd: indexTip,
    );
    if (angle == null) return;

    final rayIntersection = geometry.forwardRayIntersection2D(
      firstStart: thumbTip,
      firstThrough: thumbIp,
      secondStart: indexTip,
      secondThrough: indexDip,
      minForwardScale: HandGestureThresholds.zoomInMinForwardRayScale,
      parallelToleranceDegrees:
          HandGestureThresholds.zoomInParallelRayToleranceDegrees,
      minParallelLineSeparation:
          geometry.handSizeFromBoundingBox(currentHand.boundingBox) *
          HandGestureThresholds.zoomInParallelMinLineSeparationRatio,
    );
    final isInExpectedHandQuadrant =
        rayIntersection != null &&
        geometry.isForwardRayRelationInHandQuadrant2D(
          relation: rayIntersection,
          firstStart: thumbTip,
          firstThrough: thumbIp,
          secondStart: indexTip,
          secondThrough: indexDip,
          imageSize: imageSize,
          handedness: currentHand.handedness,
          mirrorHorizontally: mirrorHorizontally,
        );
    final intersection = rayIntersection?.point;
    final hasAcceptedIntersection =
        rayIntersection != null && isInExpectedHandQuadrant;
    final color = hasAcceptedIntersection
        ? const Color(0xFF00E5FF)
        : const Color(0xFFFFA726);
    final mapPoint = _pointMapper(size);
    final mappedThumbTip = mapPoint(Offset(thumbTip.x, thumbTip.y));
    final mappedThumbIp = mapPoint(Offset(thumbIp.x, thumbIp.y));
    final mappedIndexTip = mapPoint(Offset(indexTip.x, indexTip.y));
    final mappedIndexDip = mapPoint(Offset(indexDip.x, indexDip.y));
    final mappedIntersection = intersection == null
        ? null
        : mapPoint(intersection);
    final intersectionIsVisible =
        mappedIntersection != null &&
        (Offset.zero & size).deflate(18).contains(mappedIntersection);

    final thumbRayTarget = intersectionIsVisible
        ? mappedIntersection
        : _rayTargetInsideCanvas(
            through: mappedThumbIp,
            direction: mappedThumbIp - mappedThumbTip,
            canvasSize: size,
          );
    final indexRayTarget = intersectionIsVisible
        ? mappedIntersection
        : _rayTargetInsideCanvas(
            through: mappedIndexDip,
            direction: mappedIndexDip - mappedIndexTip,
            canvasSize: size,
          );

    canvas.save();
    canvas.clipRect(Offset.zero & size);

    final rayPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round
      ..color = color;

    _drawRay(
      canvas,
      start: mappedThumbTip,
      through: mappedThumbIp,
      target: thumbRayTarget,
      paint: rayPaint,
      extendPastTarget: intersectionIsVisible ? 22 : 0,
    );
    _drawRay(
      canvas,
      start: mappedIndexTip,
      through: mappedIndexDip,
      target: indexRayTarget,
      paint: rayPaint,
      extendPastTarget: intersectionIsVisible ? 22 : 0,
    );

    _drawKeyPoint(canvas, mappedThumbTip, '4');
    _drawKeyPoint(canvas, mappedThumbIp, '3');
    _drawKeyPoint(canvas, mappedIndexTip, '8');
    _drawKeyPoint(canvas, mappedIndexDip, '7');

    if (intersectionIsVisible) {
      _drawIntersection(canvas, mappedIntersection, color);
      _drawAngle(
        canvas,
        intersection: mappedIntersection,
        thumbPoint: mappedThumbIp,
        indexPoint: mappedIndexDip,
        angle: angle,
        color: color,
      );
      if (!isInExpectedHandQuadrant) {
        _drawLabel(
          canvas,
          _wrongHandQuadrantStatus(currentHand.handedness),
          mappedIntersection + const Offset(10, 10),
          color,
        );
      }
    } else {
      final labelPoint = Offset(
        (mappedThumbIp.dx + mappedIndexDip.dx) / 2,
        (mappedThumbIp.dy + mappedIndexDip.dy) / 2,
      );
      final status = switch (rayIntersection?.kind) {
        ForwardRayIntersectionKind.finite when !isInExpectedHandQuadrant =>
          _wrongHandQuadrantStatus(currentHand.handedness),
        ForwardRayIntersectionKind.finite => 'forward intersection off-screen',
        ForwardRayIntersectionKind.atInfinity when !isInExpectedHandQuadrant =>
          'parallel points outside required quadrant',
        ForwardRayIntersectionKind.atInfinity => 'intersection at infinity',
        null
            when angle <=
                HandGestureThresholds.zoomInParallelRayToleranceDegrees +
                    1e-9 =>
          'parallel lines too close',
        null => 'no forward intersection',
      };
      _drawLabel(
        canvas,
        'Zoom In ${angle.toStringAsFixed(1)}°\n$status',
        labelPoint + const Offset(10, 10),
        color,
      );
    }

    canvas.restore();
  }

  String _wrongHandQuadrantStatus(Handedness? handedness) {
    return switch (handedness) {
      Handedness.right => 'intersection must be in quadrant 4',
      Handedness.left => 'intersection must be in quadrant 3',
      null => 'handedness required',
    };
  }

  HandLandmark? _visibleLandmark(Hand hand, HandLandmarkType type) {
    return geometry.visibleLandmark(
      hand,
      type,
      minVisibility: HandGestureThresholds.zoomMinLandmarkVisibility,
    );
  }

  Offset _rayTargetInsideCanvas({
    required Offset through,
    required Offset direction,
    required Size canvasSize,
  }) {
    if (!direction.distance.isFinite || direction.distance <= 1e-9) {
      return through;
    }

    const inset = 18.0;
    final bounds = Rect.fromLTRB(
      inset,
      inset,
      math.max(inset, canvasSize.width - inset),
      math.max(inset, canvasSize.height - inset),
    );
    final unit = direction / direction.distance;
    final distances = <double>[];
    if (unit.dx > 1e-9) distances.add((bounds.right - through.dx) / unit.dx);
    if (unit.dx < -1e-9) distances.add((bounds.left - through.dx) / unit.dx);
    if (unit.dy > 1e-9) distances.add((bounds.bottom - through.dy) / unit.dy);
    if (unit.dy < -1e-9) distances.add((bounds.top - through.dy) / unit.dy);
    final forwardDistances = distances
        .where((distance) => distance.isFinite && distance > 0)
        .toList(growable: false);
    if (forwardDistances.isEmpty) {
      return through + unit * math.max(canvasSize.width, canvasSize.height);
    }
    return through + unit * forwardDistances.reduce(math.min);
  }

  void _drawRay(
    Canvas canvas, {
    required Offset start,
    required Offset through,
    required Offset target,
    required Paint paint,
    double extendPastTarget = 22,
  }) {
    final finalDirection = target - through;
    final segmentDirection = through - start;
    final normalizedDirection = finalDirection.distance > 1e-9
        ? finalDirection / finalDirection.distance
        : segmentDirection.distance > 1e-9
        ? segmentDirection / segmentDirection.distance
        : const Offset(0, 1);
    final end = target + normalizedDirection * extendPastTarget;
    canvas.drawLine(start, end, paint);
    _drawArrowHead(canvas, end, normalizedDirection, paint);
  }

  void _drawArrowHead(
    Canvas canvas,
    Offset end,
    Offset direction,
    Paint paint,
  ) {
    final normal = Offset(-direction.dy, direction.dx);
    final base = end - direction * 12;
    final path = Path()
      ..moveTo(end.dx, end.dy)
      ..lineTo((base + normal * 5).dx, (base + normal * 5).dy)
      ..moveTo(end.dx, end.dy)
      ..lineTo((base - normal * 5).dx, (base - normal * 5).dy);
    canvas.drawPath(path, paint);
  }

  void _drawKeyPoint(Canvas canvas, Offset point, String label) {
    final fill = Paint()
      ..style = PaintingStyle.fill
      ..color = const Color(0xFFFFF176);
    final border = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..color = Colors.black;
    canvas.drawCircle(point, 5, fill);
    canvas.drawCircle(point, 5, border);
    _drawLabel(canvas, label, point + const Offset(7, -16), Colors.white);
  }

  void _drawIntersection(Canvas canvas, Offset point, Color color) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..color = color;
    canvas.drawCircle(point, 8, paint);
    canvas.drawLine(
      point - const Offset(12, 0),
      point + const Offset(12, 0),
      paint,
    );
    canvas.drawLine(
      point - const Offset(0, 12),
      point + const Offset(0, 12),
      paint,
    );
  }

  void _drawAngle(
    Canvas canvas, {
    required Offset intersection,
    required Offset thumbPoint,
    required Offset indexPoint,
    required double angle,
    required Color color,
  }) {
    final thumbVector = thumbPoint - intersection;
    final indexVector = indexPoint - intersection;
    if (thumbVector.distance <= 1e-9 || indexVector.distance <= 1e-9) return;

    final thumbAngle = math.atan2(thumbVector.dy, thumbVector.dx);
    final indexAngle = math.atan2(indexVector.dy, indexVector.dx);
    var sweep = indexAngle - thumbAngle;
    while (sweep <= -math.pi) {
      sweep += 2 * math.pi;
    }
    while (sweep > math.pi) {
      sweep -= 2 * math.pi;
    }

    const radius = 34.0;
    final arcPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..color = color;
    canvas.drawArc(
      Rect.fromCircle(center: intersection, radius: radius),
      thumbAngle,
      sweep,
      false,
      arcPaint,
    );

    final labelAngle = thumbAngle + sweep / 2;
    final labelPoint =
        intersection +
        Offset(math.cos(labelAngle), math.sin(labelAngle)) * (radius + 16);
    _drawLabel(
      canvas,
      'Zoom In ${angle.toStringAsFixed(1)}°',
      labelPoint,
      color,
    );
  }

  void _drawLabel(Canvas canvas, String text, Offset point, Color color) {
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w800,
          shadows: const [Shadow(color: Colors.black, blurRadius: 4)],
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    painter.paint(canvas, point);
  }

  Offset Function(Offset) _pointMapper(Size canvasSize) {
    final effectiveTurns = useRecordingPreviewMapping
        ? _bestQuarterTurnsForCanvas(canvasSize)
        : previewQuarterTurns % 4;
    final sourceSize = _sourceSizeForTurns(effectiveTurns);

    return (Offset sourcePoint) {
      final normalized = Offset(
        sourcePoint.dx / imageSize.width,
        sourcePoint.dy / imageSize.height,
      );

      if (!useRecordingPreviewMapping) {
        final mirrored = mirrorHorizontally
            ? Offset(1 - normalized.dx, normalized.dy)
            : normalized;
        final rotated = _rotateNormalizedPoint(mirrored, effectiveTurns);
        return Offset(
          rotated.dx * canvasSize.width,
          rotated.dy * canvasSize.height,
        );
      }

      final rotated = _rotateNormalizedPoint(normalized, effectiveTurns);
      final mirrored = mirrorHorizontally
          ? Offset(1 - rotated.dx, rotated.dy)
          : rotated;
      return _mapCoverPoint(
        normalizedPoint: mirrored,
        sourceSize: sourceSize,
        canvasSize: canvasSize,
      );
    };
  }

  int _bestQuarterTurnsForCanvas(Size canvasSize) {
    final requestedTurns = previewQuarterTurns % 4;
    final normalDiff = _aspectDiff(imageSize, canvasSize);
    final rotatedDiff = _aspectDiff(
      _sourceSizeForTurns(requestedTurns),
      canvasSize,
    );
    return rotatedDiff < normalDiff ? requestedTurns : 0;
  }

  double _aspectDiff(Size sourceSize, Size canvasSize) {
    return ((sourceSize.width / sourceSize.height) -
            (canvasSize.width / canvasSize.height))
        .abs();
  }

  Size _sourceSizeForTurns(int quarterTurns) {
    return (quarterTurns % 4).isOdd
        ? Size(imageSize.height, imageSize.width)
        : imageSize;
  }

  Offset _rotateNormalizedPoint(Offset point, int quarterTurns) {
    switch (quarterTurns % 4) {
      case 1:
        return Offset(1 - point.dy, point.dx);
      case 2:
        return Offset(1 - point.dx, 1 - point.dy);
      case 3:
        return Offset(point.dy, 1 - point.dx);
      default:
        return point;
    }
  }

  Offset _mapCoverPoint({
    required Offset normalizedPoint,
    required Size sourceSize,
    required Size canvasSize,
  }) {
    final scaleX = canvasSize.width / sourceSize.width;
    final scaleY = canvasSize.height / sourceSize.height;
    final scale = math.max(scaleX, scaleY);
    final fittedWidth = sourceSize.width * scale;
    final fittedHeight = sourceSize.height * scale;

    return Offset(
      (canvasSize.width - fittedWidth) / 2 +
          normalizedPoint.dx * sourceSize.width * scale,
      (canvasSize.height - fittedHeight) / 2 +
          normalizedPoint.dy * sourceSize.height * scale,
    );
  }

  @override
  bool shouldRepaint(covariant ZoomInDebugOverlayPainter oldDelegate) {
    return oldDelegate.hand != hand ||
        oldDelegate.imageSize != imageSize ||
        oldDelegate.mirrorHorizontally != mirrorHorizontally ||
        oldDelegate.previewQuarterTurns != previewQuarterTurns ||
        oldDelegate.useRecordingPreviewMapping != useRecordingPreviewMapping;
  }
}
