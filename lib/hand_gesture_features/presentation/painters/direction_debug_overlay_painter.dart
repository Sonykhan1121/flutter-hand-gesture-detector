import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:hand_detection/hand_detection.dart';

import '../../domain/enums/hand_move_direction.dart';
import '../../domain/services/hand_geometry_service.dart';

/// Draws direction sectors and the full-screen index axis used for detection.
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
    }
    _drawStatus(canvas, size);
    canvas.restore();
  }

  void _drawDirectionSectors(Canvas canvas, Size size) {
    final guidePaint =
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5
          ..color = const Color(0x99FFFFFF);

    canvas.drawLine(Offset.zero, Offset(size.width, size.height), guidePaint);
    canvas.drawLine(Offset(size.width, 0), Offset(0, size.height), guidePaint);

    _drawZoneLabel(canvas, 'UP', Offset(size.width / 2, 42));
    _drawZoneLabel(canvas, 'LEFT', Offset(34, size.height / 2));
    _drawZoneLabel(canvas, 'RIGHT', Offset(size.width - 38, size.height / 2));
    _drawZoneLabel(canvas, 'DOWN', Offset(size.width / 2, size.height - 42));
  }

  void _drawIndexAxis(Canvas canvas, Size size, Hand currentHand) {
    final usesDownAxis =
        candidateDirection == HandMoveDirection.down ||
        (candidateDirection == HandMoveDirection.none &&
            acceptedDirection == HandMoveDirection.down);
    final baseType =
        usesDownAxis
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
    final color =
        acceptedDirection != HandMoveDirection.none
            ? const Color(0xFF69F0AE)
            : candidateDirection != HandMoveDirection.none
            ? const Color(0xFFFFAB40)
            : const Color(0xFF40C4FF);
    final axisPaint =
        Paint()
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

    _drawLandmarkPoint(canvas, mappedBase, usesDownAxis ? '6' : '5', color);
    _drawLandmarkPoint(canvas, mappedTip, '8', color);
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
    final path =
        Path()
          ..moveTo(end.dx, end.dy)
          ..lineTo((base + normal * 7).dx, (base + normal * 7).dy)
          ..moveTo(end.dx, end.dy)
          ..lineTo((base - normal * 7).dx, (base - normal * 7).dy);
    canvas.drawPath(path, paint);
  }

  void _drawLandmarkPoint(
    Canvas canvas,
    Offset point,
    String label,
    Color color,
  ) {
    final fill =
        Paint()
          ..style = PaintingStyle.fill
          ..color = color;
    final border =
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = Colors.black;
    canvas.drawCircle(point, 6, fill);
    canvas.drawCircle(point, 6, border);
    _drawText(
      canvas,
      label,
      point + const Offset(8, -18),
      color: Colors.white,
      fontSize: 12,
    );
  }

  void _drawStatus(Canvas canvas, Size size) {
    final usesDownAxis =
        candidateDirection == HandMoveDirection.down ||
        (candidateDirection == HandMoveDirection.none &&
            acceptedDirection == HandMoveDirection.down);
    final axisLabel = usesDownAxis ? '6 → 8' : '5 → 8';
    final candidate = candidateDirection.name.toUpperCase();
    final accepted = acceptedDirection.name.toUpperCase();
    final text =
        'Index axis $axisLabel  |  Candidate: $candidate  |  Accepted: $accepted\n'
        '$debugSummary';
    final textPainter = TextPainter(
      text: TextSpan(
        text: text,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 11,
          fontWeight: FontWeight.w700,
          height: 1.25,
          shadows: [Shadow(color: Colors.black, blurRadius: 4)],
        ),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 3,
      ellipsis: '…',
    )..layout(maxWidth: math.max(0, size.width - 32));

    const origin = Offset(16, 14);
    final background = RRect.fromRectAndRadius(
      Rect.fromLTWH(
        origin.dx - 7,
        origin.dy - 5,
        textPainter.width + 14,
        textPainter.height + 10,
      ),
      const Radius.circular(7),
    );
    canvas.drawRRect(
      background,
      Paint()
        ..style = PaintingStyle.fill
        ..color = const Color(0xB3000000),
    );
    textPainter.paint(canvas, origin);
  }

  void _drawZoneLabel(Canvas canvas, String text, Offset center) {
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: const TextStyle(
          color: Color(0xCCFFFFFF),
          fontSize: 12,
          fontWeight: FontWeight.w900,
          shadows: [Shadow(color: Colors.black, blurRadius: 4)],
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    painter.paint(
      canvas,
      center - Offset(painter.width / 2, painter.height / 2),
    );
  }

  void _drawText(
    Canvas canvas,
    String text,
    Offset point, {
    required Color color,
    required double fontSize,
  }) {
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: color,
          fontSize: fontSize,
          fontWeight: FontWeight.w900,
          shadows: const [Shadow(color: Colors.black, blurRadius: 4)],
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    painter.paint(canvas, point);
  }

  Offset Function(Offset) _pointMapper(Size canvasSize) {
    final effectiveTurns =
        useRecordingPreviewMapping
            ? _bestQuarterTurnsForCanvas(canvasSize)
            : previewQuarterTurns % 4;
    final sourceSize = _sourceSizeForTurns(effectiveTurns);

    return (Offset sourcePoint) {
      final normalized = Offset(
        sourcePoint.dx / imageSize.width,
        sourcePoint.dy / imageSize.height,
      );

      if (!useRecordingPreviewMapping) {
        final mirrored =
            mirrorHorizontally
                ? Offset(1 - normalized.dx, normalized.dy)
                : normalized;
        final rotated = _rotateNormalizedPoint(mirrored, effectiveTurns);
        return Offset(
          rotated.dx * canvasSize.width,
          rotated.dy * canvasSize.height,
        );
      }

      final rotated = _rotateNormalizedPoint(normalized, effectiveTurns);
      final mirrored =
          mirrorHorizontally ? Offset(1 - rotated.dx, rotated.dy) : rotated;
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
        oldDelegate.debugSummary != debugSummary ||
        oldDelegate.previewQuarterTurns != previewQuarterTurns ||
        oldDelegate.useRecordingPreviewMapping != useRecordingPreviewMapping;
  }
}
