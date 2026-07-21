import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:hand_detection/hand_detection.dart';

import '../../domain/constants/hand_gesture_thresholds.dart';
import '../../domain/enums/hand_move_direction.dart';
import '../../domain/services/hand_geometry_service.dart';

/// Visualizes the live four-way direction decision without changing it.
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

  static const _cyan = Color(0xFF00E5FF);
  static const _green = Color(0xFF69F0AE);
  static const _red = Color(0xFFFF5252);
  static const _yellow = Color(0xFFFFD740);

  static const _foldFingerSpecs = [
    _FoldFingerSpec(
      name: 'Middle',
      types: [
        HandLandmarkType.middleFingerMCP,
        HandLandmarkType.middleFingerPIP,
        HandLandmarkType.middleFingerDIP,
        HandLandmarkType.middleFingerTip,
      ],
      numbers: ['9', '10', '11', '12'],
    ),
    _FoldFingerSpec(
      name: 'Ring',
      types: [
        HandLandmarkType.ringFingerMCP,
        HandLandmarkType.ringFingerPIP,
        HandLandmarkType.ringFingerDIP,
        HandLandmarkType.ringFingerTip,
      ],
      numbers: ['13', '14', '15', '16'],
    ),
    _FoldFingerSpec(
      name: 'Pinky',
      types: [
        HandLandmarkType.pinkyMCP,
        HandLandmarkType.pinkyPIP,
        HandLandmarkType.pinkyDIP,
        HandLandmarkType.pinkyTip,
      ],
      numbers: ['17', '18', '19', '20'],
    ),
  ];

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
    if (currentHand == null) {
      _drawNoHandPanel(canvas, size);
      canvas.restore();
      return;
    }

    final mapPoint = _pointMapper(size);
    final mcpAngle = _visibleIndexDirectionAngleDegrees(currentHand);
    final angleSector = mcpAngle == null
        ? HandMoveDirection.none
        : _directionForAngle(mcpAngle);
    final nearestDirection = mcpAngle == null
        ? HandMoveDirection.none
        : _nearestDirectionForAngle(mcpAngle);
    final displayDirection = acceptedDirection != HandMoveDirection.none
        ? acceptedDirection
        : candidateDirection != HandMoveDirection.none
        ? candidateDirection
        : angleSector != HandMoveDirection.none
        ? angleSector
        : nearestDirection;
    final directionAngle = _visibleDirectionAngleDegrees(
      currentHand,
      displayDirection,
    );
    final indexEvaluation = _evaluateIndex(currentHand, displayDirection);
    final foldEvaluations = _evaluateFoldedFingers(currentHand);

    _drawIndexAxis(
      canvas: canvas,
      size: size,
      hand: currentHand,
      direction: displayDirection,
      angle: directionAngle,
      mapPoint: mapPoint,
    );
    for (final evaluation in foldEvaluations) {
      _drawFoldDistanceGraph(
        canvas: canvas,
        evaluation: evaluation,
        mapPoint: mapPoint,
      );
    }
    _drawStatusPanel(
      canvas: canvas,
      size: size,
      displayDirection: displayDirection,
      directionAngle: directionAngle,
      indexEvaluation: indexEvaluation,
      foldEvaluations: foldEvaluations,
    );
    canvas.restore();
  }

  void _drawDirectionSectors(Canvas canvas, Size size) {
    final guidePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..color = const Color(0xCCFFFFFF);
    canvas.drawLine(Offset.zero, Offset(size.width, size.height), guidePaint);
    canvas.drawLine(Offset(size.width, 0), Offset(0, size.height), guidePaint);

    _drawSectorLabel(
      canvas,
      center: Offset(size.width / 2, size.height * 0.32),
      direction: HandMoveDirection.up,
      cardinalAngle: 90,
      range:
          '${_degrees(HandGestureThresholds.movingUpInitialMinDirectionAngleDegrees)}–'
          '${_degrees(HandGestureThresholds.movingUpInitialMaxDirectionAngleDegrees)}',
    );
    _drawSectorLabel(
      canvas,
      center: Offset(size.width * 0.14, size.height * 0.66),
      direction: HandMoveDirection.left,
      cardinalAngle: 180,
      range:
          '${_degrees(HandGestureThresholds.movingLeftMinDirectionAngleDegrees)}–'
          '${_degrees(HandGestureThresholds.movingLeftMaxDirectionAngleDegrees)}',
    );
    _drawSectorLabel(
      canvas,
      center: Offset(size.width * 0.86, size.height * 0.66),
      direction: HandMoveDirection.right,
      cardinalAngle: 0,
      range:
          '${_degrees(HandGestureThresholds.movingRightMinDirectionAngleDegrees)}–360° / '
          '0°–${_degrees(HandGestureThresholds.movingRightMaxDirectionAngleDegrees)}',
    );
    _drawSectorLabel(
      canvas,
      center: Offset(size.width / 2, size.height * 0.89),
      direction: HandMoveDirection.down,
      cardinalAngle: 270,
      range:
          '${_degrees(HandGestureThresholds.movingDownInitialMinDirectionAngleDegrees)}–'
          '${_degrees(HandGestureThresholds.movingDownInitialMaxDirectionAngleDegrees)}',
    );
  }

  void _drawSectorLabel(
    Canvas canvas, {
    required Offset center,
    required HandMoveDirection direction,
    required int cardinalAngle,
    required String range,
  }) {
    final isAccepted = acceptedDirection == direction;
    final isCandidate = !isAccepted && candidateDirection == direction;
    final color = isAccepted
        ? _green
        : isCandidate
        ? _yellow
        : Colors.white.withValues(alpha: 0.86);
    final painter = TextPainter(
      text: TextSpan(
        text:
            '${direction.name.toUpperCase()}  $cardinalAngle°\n'
            '$range',
        style: TextStyle(
          color: color,
          fontSize: 11,
          height: 1.15,
          fontWeight: FontWeight.w800,
          shadows: const [Shadow(color: Colors.black, blurRadius: 5)],
        ),
      ),
      textAlign: TextAlign.center,
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: 128);
    painter.paint(
      canvas,
      center - Offset(painter.width / 2, painter.height / 2),
    );
  }

  String _degrees(double value) => '${value.toStringAsFixed(0)}°';

  void _drawIndexAxis({
    required Canvas canvas,
    required Size size,
    required Hand hand,
    required HandMoveDirection direction,
    required double? angle,
    required Offset Function(Offset) mapPoint,
  }) {
    final chainTypes = const [
      HandLandmarkType.indexFingerMCP,
      HandLandmarkType.indexFingerPIP,
      HandLandmarkType.indexFingerDIP,
      HandLandmarkType.indexFingerTip,
    ];
    final chain = geometry.visibleFingerChain(hand, chainTypes);
    if (chain == null) return;

    final baseIndex = direction == HandMoveDirection.down ? 1 : 0;
    final mappedPoints = chain
        .map((point) => mapPoint(Offset(point.x, point.y)))
        .toList(growable: false);
    final base = mappedPoints[baseIndex];
    final tip = mappedPoints[3];
    final axisVector = tip - base;
    final axisDistance = axisVector.distance;
    if (!axisDistance.isFinite || axisDistance <= 1e-9) return;
    final axisDirection = axisVector / axisDistance;
    final extent =
        math.sqrt(size.width * size.width + size.height * size.height) * 2;
    final axisPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round
      ..color = _cyan;

    canvas.drawLine(
      base - axisDirection * extent,
      base + axisDirection * extent,
      axisPaint,
    );
    for (var index = 0; index < mappedPoints.length - 1; index += 1) {
      canvas.drawLine(mappedPoints[index], mappedPoints[index + 1], axisPaint);
    }
    final forwardEdge = _forwardEdgePoint(
      start: tip,
      direction: axisDirection,
      size: size,
    );
    if (forwardEdge != null) {
      _drawArrowHead(
        canvas,
        end: forwardEdge,
        direction: axisDirection,
        paint: axisPaint,
      );
    }

    for (var index = 0; index < mappedPoints.length; index += 1) {
      _drawNumberedPoint(canvas, mappedPoints[index], '${index + 5}', _cyan);
    }
    if (angle != null) {
      final labelPoint = Offset(
        ((base.dx + tip.dx) / 2).clamp(58.0, math.max(58.0, size.width - 58)),
        ((base.dy + tip.dy) / 2 + 18).clamp(
          24.0,
          math.max(24.0, size.height - 24),
        ),
      );
      _drawPillText(
        canvas,
        text: 'Index direction = ${angle.toStringAsFixed(1)}°',
        center: labelPoint,
        color: _cyan,
      );
    }
  }

  List<_FoldDebugEvaluation> _evaluateFoldedFingers(Hand hand) {
    final palmWidth = _foldReferencePalmWidth(hand);
    return _foldFingerSpecs
        .map((spec) {
          final chain = spec.types
              .map((type) => geometry.visibleLandmark(hand, type))
              .toList(growable: false);
          if (palmWidth <= 0 || chain.any((point) => point == null)) {
            return _FoldDebugEvaluation(
              spec: spec,
              chain: chain,
              state: _FoldDebugState.unavailable,
            );
          }

          final points = chain.cast<HandLandmark>();
          final mcp = points[0];
          final pip = points[1];
          final dip = points[2];
          final tip = points[3];
          final isFolded =
              geometry.isFingerTopClusterFolded3D(
                mcp: mcp,
                pip: pip,
                dip: dip,
                tip: tip,
                palmWidth: palmWidth,
              ) ||
              geometry.isFingerFoldedByCompression3D(
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
          return _FoldDebugEvaluation(
            spec: spec,
            chain: chain,
            state: isFolded
                ? _FoldDebugState.folded
                : isOpen
                ? _FoldDebugState.open
                : _FoldDebugState.uncertain,
          );
        })
        .toList(growable: false);
  }

  void _drawFoldDistanceGraph({
    required Canvas canvas,
    required _FoldDebugEvaluation evaluation,
    required Offset Function(Offset) mapPoint,
  }) {
    final visibleEntries = <(int, Offset)>[];
    for (var index = 0; index < evaluation.chain.length; index += 1) {
      final landmark = evaluation.chain[index];
      if (landmark == null) continue;
      visibleEntries.add((index, mapPoint(Offset(landmark.x, landmark.y))));
    }
    if (visibleEntries.isEmpty) return;

    final pairPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round
      ..color = _red.withValues(alpha: 0.86);
    // Every pair is connected so it is visible which landmark distances are
    // being judged for the folded-finger area/compression rules.
    for (var first = 0; first < visibleEntries.length; first += 1) {
      for (
        var second = first + 1;
        second < visibleEntries.length;
        second += 1
      ) {
        canvas.drawLine(
          visibleEntries[first].$2,
          visibleEntries[second].$2,
          pairPaint,
        );
      }
    }

    final complete = visibleEntries.length == 4;
    if (complete) {
      final mcp = visibleEntries[0].$2;
      final tip = visibleEntries[3].$2;
      canvas.drawLine(
        mcp,
        tip,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3
          ..strokeCap = StrokeCap.round
          ..color = _red,
      );
      if (evaluation.state != _FoldDebugState.folded) {
        final vector = mcp - tip;
        final distance = vector.distance;
        if (distance.isFinite && distance > 1e-9) {
          final direction = vector / distance;
          _drawArrowHead(
            canvas,
            end: mcp,
            direction: direction,
            paint: Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = 3
              ..strokeCap = StrokeCap.round
              ..color = _red,
          );
        }
      }
    }

    for (final entry in visibleEntries) {
      _drawNumberedPoint(
        canvas,
        entry.$2,
        evaluation.spec.numbers[entry.$1],
        _red,
      );
    }

    final center =
        visibleEntries
            .map((entry) => entry.$2)
            .reduce((first, second) => first + second) /
        visibleEntries.length.toDouble();
    final markerCenter = center + const Offset(24, 0);
    if (evaluation.state == _FoldDebugState.folded) {
      _drawCheck(canvas, markerCenter);
    } else {
      _drawCross(canvas, markerCenter);
    }
  }

  _IndexDebugEvaluation _evaluateIndex(Hand hand, HandMoveDirection direction) {
    final chain = geometry.visibleFingerChain(hand, const [
      HandLandmarkType.indexFingerMCP,
      HandLandmarkType.indexFingerPIP,
      HandLandmarkType.indexFingerDIP,
      HandLandmarkType.indexFingerTip,
    ]);
    if (chain == null) {
      return const _IndexDebugEvaluation(
        matches: false,
        text: 'Index: points 5–8 unavailable',
        fix: 'Keep index points 5–8 visible',
      );
    }

    final angle567 = geometry.fingerJointAngleDegrees(
      mcp: chain[0],
      pip: chain[1],
      tip: chain[2],
    );
    final angle678 = geometry.fingerJointAngleDegrees(
      mcp: chain[1],
      pip: chain[2],
      tip: chain[3],
    );
    final pathLength =
        geometry.distanceBetweenLandmarks(chain[0], chain[1]) +
        geometry.distanceBetweenLandmarks(chain[1], chain[2]) +
        geometry.distanceBetweenLandmarks(chain[2], chain[3]);
    final straightness = pathLength > 0
        ? geometry.distanceBetweenLandmarks(chain[0], chain[3]) / pathLength
        : 0.0;

    switch (direction) {
      case HandMoveDirection.left:
        final matches =
            angle567 >=
                HandGestureThresholds.movingLeftIndexMinJointAngleDegrees &&
            angle678 >=
                HandGestureThresholds.movingLeftIndexMinJointAngleDegrees &&
            straightness >=
                HandGestureThresholds.movingLeftIndexMinStraightnessRatio;
        return _IndexDebugEvaluation(
          matches: matches,
          text: matches
              ? 'Index: straight enough'
              : 'Index: ${angle567.toStringAsFixed(0)}°/'
                    '${angle678.toStringAsFixed(0)}°, '
                    '${(straightness * 100).toStringAsFixed(0)}% straight',
          fix: 'Straighten points 5–8 toward LEFT',
        );
      case HandMoveDirection.right:
        final matches =
            straightness >=
            HandGestureThresholds.movingRightIndexMinStraightnessRatio;
        return _IndexDebugEvaluation(
          matches: matches,
          text: matches
              ? 'Index: straight enough'
              : 'Index: ${(straightness * 100).toStringAsFixed(0)}% straight',
          fix: 'Straighten points 5–8 toward RIGHT',
        );
      case HandMoveDirection.up:
        final matches =
            angle567 >=
                HandGestureThresholds.movingUpMinMcpPipDipJointAngleDegrees &&
            angle678 >=
                HandGestureThresholds.verticalDirectionIndexMinAngleDegrees;
        return _IndexDebugEvaluation(
          matches: matches,
          text: matches
              ? 'Index: 5–8 straight enough'
              : 'Index: 5–6–7 ${angle567.toStringAsFixed(0)}°, '
                    '6–7–8 ${angle678.toStringAsFixed(0)}°',
          fix: 'Straighten 5–8; keep 6–7–8 at least 170°',
        );
      case HandMoveDirection.down:
        final matches =
            angle678 >=
            HandGestureThresholds.verticalDirectionIndexMinAngleDegrees;
        return _IndexDebugEvaluation(
          matches: matches,
          text: matches
              ? 'Index: 6–8 straight enough'
              : 'Index: 6–7–8 ${angle678.toStringAsFixed(0)}°',
          fix: 'Straighten points 6–8 to at least 170°',
        );
      case HandMoveDirection.none:
        final matches = straightness >= 0.80;
        return _IndexDebugEvaluation(
          matches: matches,
          text: matches
              ? 'Index: straight enough'
              : 'Index: ${(straightness * 100).toStringAsFixed(0)}% straight',
          fix: 'Straighten points 5–8',
        );
    }
  }

  void _drawStatusPanel({
    required Canvas canvas,
    required Size size,
    required HandMoveDirection displayDirection,
    required double? directionAngle,
    required _IndexDebugEvaluation indexEvaluation,
    required List<_FoldDebugEvaluation> foldEvaluations,
  }) {
    final directionMatches =
        acceptedDirection != HandMoveDirection.none ||
        (displayDirection != HandMoveDirection.none &&
            directionAngle != null &&
            _isAngleForDirection(directionAngle, displayDirection));
    final directionName = displayDirection == HandMoveDirection.none
        ? 'NONE'
        : displayDirection.name.toUpperCase();
    final rows = <_StatusRow>[
      _StatusRow(
        matches: directionMatches,
        text:
            'Direction: $directionName — '
            '${directionMatches ? 'correct' : 'wrong'}'
            '${directionAngle == null ? '' : ' (${directionAngle.toStringAsFixed(1)}°)'}',
      ),
      _StatusRow(matches: indexEvaluation.matches, text: indexEvaluation.text),
      for (final evaluation in foldEvaluations)
        _StatusRow(
          matches: evaluation.state == _FoldDebugState.folded,
          text: '${evaluation.spec.name}: ${evaluation.state.label}',
        ),
    ];
    final fix = _correctionText(
      displayDirection: displayDirection,
      directionMatches: directionMatches,
      indexEvaluation: indexEvaluation,
      foldEvaluations: foldEvaluations,
    );

    final panelWidth = math.min(340.0, math.max(170.0, size.width - 24));
    final fontSize = size.width < 360 ? 10.5 : 12.0;
    final rowHeight = fontSize * 1.65;
    final panelHeight = 18 + rows.length * rowHeight + fontSize * 3.4;
    final panelRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(12, 12, panelWidth, panelHeight),
      const Radius.circular(10),
    );
    canvas.drawRRect(
      panelRect,
      Paint()..color = Colors.black.withValues(alpha: 0.78),
    );
    canvas.drawRRect(
      panelRect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = Colors.white.withValues(alpha: 0.35),
    );

    var y = 20.0;
    for (final row in rows) {
      final color = row.matches ? _green : _red;
      _paintText(
        canvas,
        text: row.matches ? '✓' : '✕',
        offset: Offset(20, y),
        maxWidth: 18,
        color: color,
        fontSize: fontSize + 2,
        fontWeight: FontWeight.w900,
      );
      _paintText(
        canvas,
        text: row.text,
        offset: Offset(42, y + 1),
        maxWidth: panelWidth - 50,
        color: Colors.white,
        fontSize: fontSize,
        fontWeight: FontWeight.w600,
      );
      y += rowHeight;
    }
    _paintText(
      canvas,
      text: 'FIX: $fix',
      offset: Offset(20, y + 3),
      maxWidth: panelWidth - 30,
      color: fix.startsWith('Pose accepted') ? _green : _red,
      fontSize: fontSize,
      fontWeight: FontWeight.w800,
    );
  }

  String _correctionText({
    required HandMoveDirection displayDirection,
    required bool directionMatches,
    required _IndexDebugEvaluation indexEvaluation,
    required List<_FoldDebugEvaluation> foldEvaluations,
  }) {
    if (!directionMatches) {
      if (displayDirection == HandMoveDirection.none) {
        return 'Point the index into one direction sector';
      }
      return 'Point the index farther ${displayDirection.name.toUpperCase()}';
    }
    if (!indexEvaluation.matches) return indexEvaluation.fix;
    for (final evaluation in foldEvaluations) {
      if (evaluation.state == _FoldDebugState.folded) continue;
      final points = evaluation.spec.numbers;
      if (evaluation.state == _FoldDebugState.unavailable) {
        return 'Keep points ${points.join(', ')} visible';
      }
      return 'Move points ${points[1]}, ${points[2]}, ${points[3]} '
          'closer to point ${points[0]}';
    }

    final summary = debugSummary.toLowerCase();
    if (summary.contains('hand moving') ||
        summary.contains('settling') ||
        summary.contains('confirming')) {
      return 'Hold the hand still until confirmation finishes';
    }
    if (summary.contains('zoom-in')) {
      return 'Change the thumb/index shape or finish Zoom In';
    }
    if (summary.contains('zoom-out')) {
      return 'Separate thumb and index or finish Zoom Out';
    }
    if (summary.contains('tip not clearly')) {
      return 'Extend point 8 farther ${displayDirection.name.toUpperCase()}';
    }
    if (summary.contains('do not rise in order')) {
      return 'Place points 5, 6, 7, 8 progressively upward';
    }
    if (summary.contains('do not descend in order')) {
      return 'Place points 6, 7, 8 progressively downward';
    }
    if (summary.contains('vertical span is too short')) {
      return 'Extend the index farther ${displayDirection.name.toUpperCase()}';
    }
    if (summary.contains('not aligned with the y-axis')) {
      return 'Align the index more vertically';
    }
    if (acceptedDirection != HandMoveDirection.none) {
      return 'Pose accepted — keep the hand steady';
    }
    return 'Hold the complete pose steady';
  }

  void _drawNoHandPanel(Canvas canvas, Size size) {
    final width = math.min(300.0, math.max(160.0, size.width - 24));
    final rect = RRect.fromRectAndRadius(
      Rect.fromLTWH(12, 12, width, 72),
      const Radius.circular(10),
    );
    canvas.drawRRect(
      rect,
      Paint()..color = Colors.black.withValues(alpha: 0.78),
    );
    _paintText(
      canvas,
      text: '✕  No reliable hand',
      offset: const Offset(20, 21),
      maxWidth: width - 30,
      color: _red,
      fontSize: 13,
      fontWeight: FontWeight.w800,
    );
    _paintText(
      canvas,
      text: 'FIX: Show one complete hand inside the camera',
      offset: const Offset(20, 45),
      maxWidth: width - 30,
      color: Colors.white,
      fontSize: 11,
      fontWeight: FontWeight.w600,
    );
  }

  void _drawNumberedPoint(
    Canvas canvas,
    Offset point,
    String number,
    Color borderColor,
  ) {
    canvas.drawCircle(
      point,
      5.5,
      Paint()
        ..style = PaintingStyle.fill
        ..color = Colors.white,
    );
    canvas.drawCircle(
      point,
      5.5,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = borderColor,
    );
    _paintText(
      canvas,
      text: number,
      offset: point + const Offset(7, -17),
      maxWidth: 28,
      color: _yellow,
      fontSize: 10,
      fontWeight: FontWeight.w900,
    );
  }

  void _drawCheck(Canvas canvas, Offset center) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..color = _green;
    final path = Path()
      ..moveTo(center.dx - 8, center.dy)
      ..lineTo(center.dx - 2, center.dy + 7)
      ..lineTo(center.dx + 10, center.dy - 9);
    canvas.drawPath(path, paint);
  }

  void _drawCross(Canvas canvas, Offset center) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round
      ..color = _red;
    canvas.drawLine(
      center + const Offset(-7, -7),
      center + const Offset(7, 7),
      paint,
    );
    canvas.drawLine(
      center + const Offset(7, -7),
      center + const Offset(-7, 7),
      paint,
    );
  }

  void _drawPillText(
    Canvas canvas, {
    required String text,
    required Offset center,
    required Color color,
  }) {
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w800,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    final rect = RRect.fromRectAndRadius(
      Rect.fromCenter(
        center: center,
        width: painter.width + 14,
        height: painter.height + 8,
      ),
      const Radius.circular(8),
    );
    canvas.drawRRect(
      rect,
      Paint()..color = Colors.black.withValues(alpha: 0.72),
    );
    painter.paint(
      canvas,
      center - Offset(painter.width / 2, painter.height / 2),
    );
  }

  void _paintText(
    Canvas canvas, {
    required String text,
    required Offset offset,
    required double maxWidth,
    required Color color,
    required double fontSize,
    required FontWeight fontWeight,
  }) {
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: color,
          fontSize: fontSize,
          height: 1.15,
          fontWeight: fontWeight,
          shadows: const [Shadow(color: Colors.black, blurRadius: 4)],
        ),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 2,
      ellipsis: '…',
    )..layout(maxWidth: maxWidth);
    painter.paint(canvas, offset);
  }

  double? _visibleIndexDirectionAngleDegrees(Hand hand) {
    final mcp = geometry.visibleLandmark(hand, HandLandmarkType.indexFingerMCP);
    final tip = geometry.visibleLandmark(hand, HandLandmarkType.indexFingerTip);
    if (mcp == null || tip == null) return null;
    return _directionAngleDegrees(mcp, tip);
  }

  double? _visibleDirectionAngleDegrees(
    Hand hand,
    HandMoveDirection direction,
  ) {
    final baseType = direction == HandMoveDirection.down
        ? HandLandmarkType.indexFingerPIP
        : HandLandmarkType.indexFingerMCP;
    final base = geometry.visibleLandmark(hand, baseType);
    final tip = geometry.visibleLandmark(hand, HandLandmarkType.indexFingerTip);
    if (base == null || tip == null) return null;
    return _directionAngleDegrees(base, tip);
  }

  double _directionAngleDegrees(HandLandmark start, HandLandmark end) {
    final startX = mirrorHorizontally ? -start.x : start.x;
    final endX = mirrorHorizontally ? -end.x : end.x;
    var angle = math.atan2(-(end.y - start.y), endX - startX) * 180 / math.pi;
    if (angle < 0) angle += 360;
    return angle;
  }

  HandMoveDirection _directionForAngle(double angle) {
    if (angle >= HandGestureThresholds.movingLeftMinDirectionAngleDegrees &&
        angle <= HandGestureThresholds.movingLeftMaxDirectionAngleDegrees) {
      return HandMoveDirection.left;
    }
    if (angle >= HandGestureThresholds.movingRightMinDirectionAngleDegrees ||
        angle <= HandGestureThresholds.movingRightMaxDirectionAngleDegrees) {
      return HandMoveDirection.right;
    }
    if (angle >=
            HandGestureThresholds.movingUpInitialMinDirectionAngleDegrees &&
        angle <=
            HandGestureThresholds.movingUpInitialMaxDirectionAngleDegrees) {
      return HandMoveDirection.up;
    }
    if (angle >=
            HandGestureThresholds.movingDownInitialMinDirectionAngleDegrees &&
        angle <=
            HandGestureThresholds.movingDownInitialMaxDirectionAngleDegrees) {
      return HandMoveDirection.down;
    }
    return HandMoveDirection.none;
  }

  bool _isAngleForDirection(double angle, HandMoveDirection direction) {
    return switch (direction) {
      HandMoveDirection.left =>
        angle >= HandGestureThresholds.movingLeftMinDirectionAngleDegrees &&
            angle <= HandGestureThresholds.movingLeftMaxDirectionAngleDegrees,
      HandMoveDirection.right =>
        angle >= HandGestureThresholds.movingRightMinDirectionAngleDegrees ||
            angle <= HandGestureThresholds.movingRightMaxDirectionAngleDegrees,
      HandMoveDirection.up =>
        angle >=
                HandGestureThresholds.movingUpInitialMinDirectionAngleDegrees &&
            angle <=
                HandGestureThresholds.movingUpInitialMaxDirectionAngleDegrees,
      HandMoveDirection.down =>
        angle >=
                HandGestureThresholds
                    .movingDownInitialMinDirectionAngleDegrees &&
            angle <=
                HandGestureThresholds.movingDownInitialMaxDirectionAngleDegrees,
      HandMoveDirection.none => false,
    };
  }

  HandMoveDirection _nearestDirectionForAngle(double angle) {
    const cardinals = [
      (HandMoveDirection.right, 0.0),
      (HandMoveDirection.up, 90.0),
      (HandMoveDirection.left, 180.0),
      (HandMoveDirection.down, 270.0),
    ];
    var nearest = cardinals.first;
    var nearestDistance = _angularDistance(angle, nearest.$2);
    for (final candidate in cardinals.skip(1)) {
      final distance = _angularDistance(angle, candidate.$2);
      if (distance < nearestDistance) {
        nearest = candidate;
        nearestDistance = distance;
      }
    }
    return nearest.$1;
  }

  double _angularDistance(double first, double second) {
    final difference = (first - second).abs() % 360;
    return math.min(difference, 360 - difference);
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
            .toList();
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
    Canvas canvas, {
    required Offset end,
    required Offset direction,
    required Paint paint,
  }) {
    final normal = Offset(-direction.dy, direction.dx);
    final base = end - direction * 14;
    final path = Path()
      ..moveTo(end.dx, end.dy)
      ..lineTo((base + normal * 6).dx, (base + normal * 6).dy)
      ..moveTo(end.dx, end.dy)
      ..lineTo((base - normal * 6).dx, (base - normal * 6).dy);
    canvas.drawPath(path, paint);
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
        oldDelegate.debugSummary != debugSummary ||
        oldDelegate.previewQuarterTurns != previewQuarterTurns ||
        oldDelegate.useRecordingPreviewMapping != useRecordingPreviewMapping;
  }
}

class _FoldFingerSpec {
  const _FoldFingerSpec({
    required this.name,
    required this.types,
    required this.numbers,
  });

  final String name;
  final List<HandLandmarkType> types;
  final List<String> numbers;
}

enum _FoldDebugState {
  folded('folded'),
  open('too open'),
  uncertain('not folded enough'),
  unavailable('points unavailable');

  const _FoldDebugState(this.label);
  final String label;
}

class _FoldDebugEvaluation {
  const _FoldDebugEvaluation({
    required this.spec,
    required this.chain,
    required this.state,
  });

  final _FoldFingerSpec spec;
  final List<HandLandmark?> chain;
  final _FoldDebugState state;
}

class _IndexDebugEvaluation {
  const _IndexDebugEvaluation({
    required this.matches,
    required this.text,
    required this.fix,
  });

  final bool matches;
  final String text;
  final String fix;
}

class _StatusRow {
  const _StatusRow({required this.matches, required this.text});

  final bool matches;
  final String text;
}
