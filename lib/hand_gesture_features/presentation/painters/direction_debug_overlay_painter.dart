import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:hand_detection/hand_detection.dart';

import '../../domain/enums/hand_move_direction.dart';
import '../../domain/services/hand_geometry_service.dart';

/// Draws direction sectors, the index axis, and the exact joint-angle geometry.
class DirectionDebugOverlayPainter extends CustomPainter {
  const DirectionDebugOverlayPainter({
    required this.hand,
    required this.imageSize,
    required this.mirrorHorizontally,
    required this.candidateDirection,
    required this.acceptedDirection,
    required this.debugSummary,
    this.previewQuarterTurns = 0,
    this.useRecordingPreviewMapping = false,
    this.geometry = const HandGeometryService(),
  });

  final Hand? hand;
  final Size imageSize;
  final bool mirrorHorizontally;
  final HandMoveDirection candidateDirection;
  final HandMoveDirection acceptedDirection;

  /// Retained for caller compatibility; direction debug text is not painted.
  final String debugSummary;
  final int previewQuarterTurns;
  final bool useRecordingPreviewMapping;
  final HandGeometryService geometry;

  @override
  void paint(Canvas canvas, Size size) {
    if (imageSize.width <= 0 ||
        imageSize.height <= 0 ||
        size.width <= 0 ||
        size.height <= 0) {
      return;
    }

    canvas.save();
    canvas.clipRect(Offset.zero & size);
    _drawDirectionSectors(canvas, size);

    final currentHand = hand;
    if (currentHand != null) {
      _drawIndexAxis(canvas, size, currentHand);
      _drawJointAngleGeometry(canvas, size, currentHand);
    }
    canvas.restore();
  }

  void _drawDirectionSectors(Canvas canvas, Size size) {
    final guidePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..color = const Color(0x99FFFFFF);

    canvas.drawLine(Offset.zero, Offset(size.width, size.height), guidePaint);
    canvas.drawLine(Offset(size.width, 0), Offset(0, size.height), guidePaint);
  }

  void _drawIndexAxis(Canvas canvas, Size size, Hand currentHand) {
    final usesDownAxis =
        candidateDirection == HandMoveDirection.down ||
        (candidateDirection == HandMoveDirection.none &&
            acceptedDirection == HandMoveDirection.down);
    final baseType = usesDownAxis
        ? HandLandmarkType.indexFingerPIP
        : HandLandmarkType.indexFingerMCP;
    final base = geometry.visibleLandmark(currentHand, baseType);
    final tip = geometry.visibleLandmark(
      currentHand,
      HandLandmarkType.indexFingerTip,
    );
    if (base == null || tip == null) return;

    final mapPoint = _pointMapper(size);
    final mappedBase = mapPoint(Offset(base.x, base.y));
    final mappedTip = mapPoint(Offset(tip.x, tip.y));
    final direction = mappedTip - mappedBase;
    if (!direction.distance.isFinite || direction.distance <= 1e-9) return;

    final unit = direction / direction.distance;
    final extent =
        math.sqrt(size.width * size.width + size.height * size.height) * 2;
    final color = acceptedDirection != HandMoveDirection.none
        ? const Color(0xFF69F0AE)
        : candidateDirection != HandMoveDirection.none
        ? const Color(0xFFFFAB40)
        : const Color(0xFF40C4FF);
    final axisPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round
      ..color = color;

    // This is an infinite line clipped to the camera preview, so it reaches
    // both screen edges even though the physical finger is short.
    canvas.drawLine(
      mappedBase - unit * extent,
      mappedBase + unit * extent,
      axisPaint,
    );

    final forwardEdge = _forwardEdgePoint(
      start: mappedTip,
      direction: unit,
      size: size,
    );
    if (forwardEdge != null) {
      _drawArrowHead(canvas, forwardEdge, unit, axisPaint);
    }

    _drawLandmarkPoint(canvas, mappedBase, color);
    _drawLandmarkPoint(canvas, mappedTip, color);
  }

  void _drawJointAngleGeometry(Canvas canvas, Size size, Hand currentHand) {
    final direction = candidateDirection != HandMoveDirection.none
        ? candidateDirection
        : acceptedDirection;
    if (direction == HandMoveDirection.none) return;

    final mapPoint = _pointMapper(size);
    const indexColor = Color(0xFF00E5FF);
    void drawIndexAngle({
      required HandLandmarkType first,
      required HandLandmarkType center,
      required HandLandmarkType last,
    }) {
      _drawJointAngle(
        canvas: canvas,
        hand: currentHand,
        mapPoint: mapPoint,
        firstType: first,
        centerType: center,
        lastType: last,
        color: indexColor,
      );
    }

    switch (direction) {
      case HandMoveDirection.left:
        drawIndexAngle(
          first: HandLandmarkType.indexFingerMCP,
          center: HandLandmarkType.indexFingerPIP,
          last: HandLandmarkType.indexFingerDIP,
        );
        drawIndexAngle(
          first: HandLandmarkType.indexFingerPIP,
          center: HandLandmarkType.indexFingerDIP,
          last: HandLandmarkType.indexFingerTip,
        );
        break;
      case HandMoveDirection.up:
        drawIndexAngle(
          first: HandLandmarkType.indexFingerMCP,
          center: HandLandmarkType.indexFingerPIP,
          last: HandLandmarkType.indexFingerDIP,
        );
        drawIndexAngle(
          first: HandLandmarkType.indexFingerPIP,
          center: HandLandmarkType.indexFingerDIP,
          last: HandLandmarkType.indexFingerTip,
        );
        break;
      case HandMoveDirection.down:
        drawIndexAngle(
          first: HandLandmarkType.indexFingerPIP,
          center: HandLandmarkType.indexFingerDIP,
          last: HandLandmarkType.indexFingerTip,
        );
        break;
      case HandMoveDirection.right:
      case HandMoveDirection.none:
        break;
    }

    final foldPalmWidth = _foldReferencePalmWidth(currentHand);
    for (final finger in const [
      (
        HandLandmarkType.middleFingerMCP,
        HandLandmarkType.middleFingerPIP,
        HandLandmarkType.middleFingerDIP,
        HandLandmarkType.middleFingerTip,
      ),
      (
        HandLandmarkType.ringFingerMCP,
        HandLandmarkType.ringFingerPIP,
        HandLandmarkType.ringFingerDIP,
        HandLandmarkType.ringFingerTip,
      ),
      (
        HandLandmarkType.pinkyMCP,
        HandLandmarkType.pinkyPIP,
        HandLandmarkType.pinkyDIP,
        HandLandmarkType.pinkyTip,
      ),
    ]) {
      _drawFingerAreaGeometry(
        canvas: canvas,
        hand: currentHand,
        mapPoint: mapPoint,
        mcpType: finger.$1,
        pipType: finger.$2,
        dipType: finger.$3,
        tipType: finger.$4,
        palmWidth: foldPalmWidth,
      );
    }
  }

  bool _drawJointAngle({
    required Canvas canvas,
    required Hand hand,
    required Offset Function(Offset) mapPoint,
    required HandLandmarkType firstType,
    required HandLandmarkType centerType,
    required HandLandmarkType lastType,
    required Color color,
  }) {
    final first = geometry.visibleLandmark(hand, firstType);
    final center = geometry.visibleLandmark(hand, centerType);
    final last = geometry.visibleLandmark(hand, lastType);
    if (first == null || center == null || last == null) return false;

    final firstPoint = mapPoint(Offset(first.x, first.y));
    final centerPoint = mapPoint(Offset(center.x, center.y));
    final lastPoint = mapPoint(Offset(last.x, last.y));
    final firstVector = firstPoint - centerPoint;
    final lastVector = lastPoint - centerPoint;
    if (!firstVector.distance.isFinite ||
        !lastVector.distance.isFinite ||
        firstVector.distance <= 1e-9 ||
        lastVector.distance <= 1e-9) {
      return false;
    }

    final linePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round
      ..color = color.withValues(alpha: 0.9);
    canvas.drawLine(centerPoint, firstPoint, linePaint);
    canvas.drawLine(centerPoint, lastPoint, linePaint);

    final startAngle = math.atan2(firstVector.dy, firstVector.dx);
    final endAngle = math.atan2(lastVector.dy, lastVector.dx);
    var sweepAngle = (endAngle - startAngle) % (2 * math.pi);
    if (sweepAngle > math.pi) sweepAngle -= 2 * math.pi;
    if (sweepAngle < -math.pi) sweepAngle += 2 * math.pi;
    final radius = math.max(
      12.0,
      math.min(
        26.0,
        math.min(firstVector.distance, lastVector.distance) * 0.38,
      ),
    );
    canvas.drawArc(
      Rect.fromCircle(center: centerPoint, radius: radius),
      startAngle,
      sweepAngle,
      false,
      linePaint,
    );

    _drawAnglePoint(canvas, firstPoint, color);
    _drawAnglePoint(canvas, centerPoint, color, isCenter: true);
    _drawAnglePoint(canvas, lastPoint, color);
    return true;
  }

  bool _drawFingerAreaGeometry({
    required Canvas canvas,
    required Hand hand,
    required Offset Function(Offset) mapPoint,
    required HandLandmarkType mcpType,
    required HandLandmarkType pipType,
    required HandLandmarkType dipType,
    required HandLandmarkType tipType,
    required double palmWidth,
  }) {
    final landmarks = [
      geometry.visibleLandmark(hand, mcpType),
      geometry.visibleLandmark(hand, pipType),
      geometry.visibleLandmark(hand, dipType),
      geometry.visibleLandmark(hand, tipType),
    ];
    if (landmarks.any((landmark) => landmark == null) || palmWidth <= 0) {
      return false;
    }

    final chain = landmarks.cast<HandLandmark>();
    final mcp = chain[0];
    final pip = chain[1];
    final dip = chain[2];
    final tip = chain[3];
    if (geometry.fingerReachAreaRatio3D(
              mcp: mcp,
              tip: tip,
              palmWidth: palmWidth,
            ) ==
            null ||
        geometry.fingerTopClusterAreaRatio3D(
              pip: pip,
              dip: dip,
              tip: tip,
              palmWidth: palmWidth,
            ) ==
            null ||
        geometry.fingerTopMaxMcpAreaRatio3D(
              mcp: mcp,
              pip: pip,
              dip: dip,
              tip: tip,
              palmWidth: palmWidth,
            ) ==
            null ||
        geometry.fingerCompressionRatio3D(
              mcp: mcp,
              pip: pip,
              dip: dip,
              tip: tip,
            ) ==
            null) {
      return false;
    }

    final isFolded =
        geometry.isFingerFoldedByCompression3D(
          mcp: mcp,
          pip: pip,
          dip: dip,
          tip: tip,
          palmWidth: palmWidth,
        ) ||
        geometry.isFingerTopClusterFolded3D(
          mcp: mcp,
          pip: pip,
          dip: dip,
          tip: tip,
          palmWidth: palmWidth,
        );
    final isOpen = geometry.isFingerClearlyOpenByArea3D(
      mcp: mcp,
      pip: pip,
      dip: dip,
      tip: tip,
      palmWidth: palmWidth,
    );
    final stateColor = isFolded
        ? const Color(0xFF69F0AE)
        : isOpen
        ? const Color(0xFFFF5252)
        : const Color(0xFFFFAB40);

    final points = chain
        .map((landmark) => mapPoint(Offset(landmark.x, landmark.y)))
        .toList(growable: false);
    final pathPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round
      ..color = const Color(0xFFB388FF).withValues(alpha: 0.9);
    final directPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round
      ..color = const Color(0xFFFF4081).withValues(alpha: 0.9);

    final reachCenter = (points.first + points.last) / 2;
    final reachRadius = math.max(
      8.0,
      (points.first - points.last).distance / 2,
    );
    canvas.drawCircle(
      reachCenter,
      reachRadius,
      Paint()
        ..style = PaintingStyle.fill
        ..color = const Color(0xFFFF9100).withValues(alpha: 0.10),
    );
    canvas.drawCircle(
      reachCenter,
      reachRadius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = const Color(0xFFFF9100).withValues(alpha: 0.9),
    );

    final topCenter = (points[1] + points[2] + points[3]) / 3;
    final topRadius = math.max(
      6.0,
      [
        points[1],
        points[2],
        points[3],
      ].map((point) => (point - topCenter).distance).reduce(math.max),
    );
    canvas.drawCircle(
      topCenter,
      topRadius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..color = const Color(0xFF00E5FF).withValues(alpha: 0.9),
    );

    _drawFoldTargetDistance(
      canvas: canvas,
      circleCenter: topCenter,
      circleRadius: topRadius,
      targetMcp: points.first,
    );

    for (var index = 0; index < points.length - 1; index += 1) {
      canvas.drawLine(points[index], points[index + 1], pathPaint);
    }
    canvas.drawLine(points.first, points.last, directPaint);

    for (var index = 0; index < points.length; index += 1) {
      _drawAnglePoint(canvas, points[index], stateColor);
    }
    return true;
  }

  /// Shows where the PIP/DIP/TIP cluster must move to close the finger.
  /// The dashed distance becomes shorter as the cluster approaches its MCP.
  void _drawFoldTargetDistance({
    required Canvas canvas,
    required Offset circleCenter,
    required double circleRadius,
    required Offset targetMcp,
  }) {
    const targetColor = Color(0xFFFFD740);
    const targetRadius = 9.0;
    final targetVector = targetMcp - circleCenter;
    final distance = targetVector.distance;

    canvas.drawCircle(
      targetMcp,
      targetRadius,
      Paint()
        ..style = PaintingStyle.fill
        ..color = targetColor.withValues(alpha: 0.15),
    );
    canvas.drawCircle(
      targetMcp,
      targetRadius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = targetColor,
    );

    if (!distance.isFinite || distance <= circleRadius + targetRadius) return;
    final direction = targetVector / distance;
    final start = circleCenter + direction * circleRadius;
    final end = targetMcp - direction * targetRadius;
    final connectorPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round
      ..color = targetColor.withValues(alpha: 0.95);
    _drawDashedLine(canvas, start, end, connectorPaint);

    final normal = Offset(-direction.dy, direction.dx);
    const arrowLength = 8.0;
    const arrowWidth = 4.0;
    final arrowBase = end - direction * arrowLength;
    final arrowPath = Path()
      ..moveTo(end.dx, end.dy)
      ..lineTo(
        (arrowBase + normal * arrowWidth).dx,
        (arrowBase + normal * arrowWidth).dy,
      )
      ..moveTo(end.dx, end.dy)
      ..lineTo(
        (arrowBase - normal * arrowWidth).dx,
        (arrowBase - normal * arrowWidth).dy,
      );
    canvas.drawPath(arrowPath, connectorPaint);
  }

  void _drawDashedLine(Canvas canvas, Offset start, Offset end, Paint paint) {
    final vector = end - start;
    final distance = vector.distance;
    if (!distance.isFinite || distance <= 1e-9) return;
    final direction = vector / distance;
    const dashLength = 6.0;
    const gapLength = 4.0;
    var offset = 0.0;
    while (offset < distance) {
      final dashEnd = math.min(offset + dashLength, distance);
      canvas.drawLine(
        start + direction * offset,
        start + direction * dashEnd,
        paint,
      );
      offset += dashLength + gapLength;
    }
  }

  void _drawAnglePoint(
    Canvas canvas,
    Offset point,
    Color color, {
    bool isCenter = false,
  }) {
    canvas.drawCircle(
      point,
      isCenter ? 7 : 4.5,
      Paint()
        ..style = PaintingStyle.fill
        ..color = color,
    );
    canvas.drawCircle(
      point,
      isCenter ? 7 : 4.5,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..color = Colors.black,
    );
  }

  double _foldReferencePalmWidth(Hand hand) {
    final mcps =
        const [
              HandLandmarkType.indexFingerMCP,
              HandLandmarkType.middleFingerMCP,
              HandLandmarkType.ringFingerMCP,
              HandLandmarkType.pinkyMCP,
            ]
            .map((type) => geometry.visibleLandmark(hand, type))
            .whereType<HandLandmark>()
            .toList(growable: false);
    var maximumDistance = 0.0;
    for (var first = 0; first < mcps.length; first += 1) {
      for (var second = first + 1; second < mcps.length; second += 1) {
        maximumDistance = math.max(
          maximumDistance,
          geometry.distanceBetweenLandmarks3D(mcps[first], mcps[second]),
        );
      }
    }
    return maximumDistance;
  }

  Offset? _forwardEdgePoint({
    required Offset start,
    required Offset direction,
    required Size size,
  }) {
    const inset = 8.0;
    final bounds = Rect.fromLTRB(
      inset,
      inset,
      math.max(inset, size.width - inset),
      math.max(inset, size.height - inset),
    );
    final distances = <double>[];
    if (direction.dx > 1e-9) {
      distances.add((bounds.right - start.dx) / direction.dx);
    } else if (direction.dx < -1e-9) {
      distances.add((bounds.left - start.dx) / direction.dx);
    }
    if (direction.dy > 1e-9) {
      distances.add((bounds.bottom - start.dy) / direction.dy);
    } else if (direction.dy < -1e-9) {
      distances.add((bounds.top - start.dy) / direction.dy);
    }

    final forward = distances
        .where((distance) => distance.isFinite && distance >= 0)
        .toList(growable: false);
    if (forward.isEmpty) return null;
    return start + direction * forward.reduce(math.min);
  }

  void _drawArrowHead(
    Canvas canvas,
    Offset end,
    Offset direction,
    Paint paint,
  ) {
    final normal = Offset(-direction.dy, direction.dx);
    final base = end - direction * 16;
    final path = Path()
      ..moveTo(end.dx, end.dy)
      ..lineTo((base + normal * 7).dx, (base + normal * 7).dy)
      ..moveTo(end.dx, end.dy)
      ..lineTo((base - normal * 7).dx, (base - normal * 7).dy);
    canvas.drawPath(path, paint);
  }

  void _drawLandmarkPoint(Canvas canvas, Offset point, Color color) {
    final fill = Paint()
      ..style = PaintingStyle.fill
      ..color = color;
    final border = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = Colors.black;
    canvas.drawCircle(point, 6, fill);
    canvas.drawCircle(point, 6, border);
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
  bool shouldRepaint(covariant DirectionDebugOverlayPainter oldDelegate) {
    return oldDelegate.hand != hand ||
        oldDelegate.imageSize != imageSize ||
        oldDelegate.mirrorHorizontally != mirrorHorizontally ||
        oldDelegate.candidateDirection != candidateDirection ||
        oldDelegate.acceptedDirection != acceptedDirection ||
        oldDelegate.previewQuarterTurns != previewQuarterTurns ||
        oldDelegate.useRecordingPreviewMapping != useRecordingPreviewMapping;
  }
}
