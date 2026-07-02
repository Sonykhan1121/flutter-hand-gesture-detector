import 'dart:collection';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:hand_detection/hand_detection.dart';

import '../constants/hand_gesture_thresholds.dart';
import '../models/open_palm_gesture_detection_result.dart';
import 'hand_geometry_service.dart';

class OpenPalmGestureDetector {
  OpenPalmGestureDetector({this.geometry = const HandGeometryService()});

  final HandGeometryService geometry;

  final ListQueue<_OpenPalmSample> _samples = ListQueue<_OpenPalmSample>();
  bool _wasDetected = false;

  OpenPalmGestureDetectionResult detect({
    required Hand hand,
    required DateTime now,
    required bool isFrontCamera,
  }) {
    final confidence = _confidence(hand, isFrontCamera: isFrontCamera);
    final confidenceThreshold =
        _wasDetected
            ? HandGestureThresholds.openPalmExitConfidence
            : HandGestureThresholds.openPalmEnterConfidence;
    final currentFrameDetected = confidence >= confidenceThreshold;

    _samples.addLast(
      _OpenPalmSample(isDetected: currentFrameDetected, time: now),
    );
    _trimSamples(now);

    final positiveSamples =
        _samples.where((sample) => sample.isDetected).length;
    final hasEnoughPositiveSamples =
        positiveSamples >=
        HandGestureThresholds.openPalmSmoothingMinPositiveSamples;
    final isDetected =
        hasEnoughPositiveSamples &&
        confidence >= HandGestureThresholds.openPalmExitConfidence;

    _wasDetected = isDetected;

    return OpenPalmGestureDetectionResult(
      isDetected: isDetected,
      confidence: confidence,
    );
  }

  void clear() {
    _samples.clear();
    _wasDetected = false;
  }

  double _confidence(Hand hand, {required bool isFrontCamera}) {
    if (!hand.hasLandmarks) return 0;

    final landmarks = _OpenPalmLandmarks.fromHand(hand, geometry);
    if (landmarks == null) return 0;

    final palmCenter = geometry.palmCenter(hand);
    if (palmCenter == null) return 0;

    final handSize = _handSize(hand);
    if (handSize <= 0) return 0;

    final indexScore = _fingerExtensionScore(
      mcp: landmarks.indexMcp,
      pip: landmarks.indexPip,
      tip: landmarks.indexTip,
      palmCenter: palmCenter,
      handSize: handSize,
    );
    final middleScore = _fingerExtensionScore(
      mcp: landmarks.middleMcp,
      pip: landmarks.middlePip,
      tip: landmarks.middleTip,
      palmCenter: palmCenter,
      handSize: handSize,
    );
    final ringScore = _fingerExtensionScore(
      mcp: landmarks.ringMcp,
      pip: landmarks.ringPip,
      tip: landmarks.ringTip,
      palmCenter: palmCenter,
      handSize: handSize,
    );
    final pinkyScore = _fingerExtensionScore(
      mcp: landmarks.pinkyMcp,
      pip: landmarks.pinkyPip,
      tip: landmarks.pinkyTip,
      palmCenter: palmCenter,
      handSize: handSize,
    );
    final thumbScore = _thumbExtensionScore(
      landmarks: landmarks,
      palmCenter: palmCenter,
      handSize: handSize,
    );
    final spreadScore = _fingerSpreadScore(
      landmarks: landmarks,
      handSize: handSize,
    );
    final palmSideScore = _palmSideScore(
      hand: hand,
      landmarks: landmarks,
      isFrontCamera: isFrontCamera,
    );
    final yAxisScore = _fingerYAxisScore(landmarks);

    final fingerScores = [
      indexScore,
      middleScore,
      ringScore,
      pinkyScore,
      thumbScore,
    ];
    final minFingerScore = fingerScores.reduce(math.min);
    final fingerConfidence = geometry.average(fingerScores);
    final confidence =
        fingerConfidence * 0.60 +
        spreadScore * 0.15 +
        palmSideScore * 0.12 +
        yAxisScore * 0.13;

    if (minFingerScore < HandGestureThresholds.openPalmMinFingerConfidence) {
      return math.min(confidence, minFingerScore);
    }

    if (spreadScore < HandGestureThresholds.openPalmMinSpreadConfidence) {
      return math.min(confidence, spreadScore);
    }

    if (palmSideScore < HandGestureThresholds.openPalmMinPalmSideConfidence) {
      return math.min(confidence, palmSideScore);
    }

    if (yAxisScore < HandGestureThresholds.openPalmMinYAxisConfidence) {
      return math.min(confidence, yAxisScore);
    }

    return confidence.clamp(0.0, 1.0);
  }

  double _fingerExtensionScore({
    required HandLandmark mcp,
    required HandLandmark pip,
    required HandLandmark tip,
    required Offset palmCenter,
    required double handSize,
  }) {
    final tipDistance = geometry.distance(tip, palmCenter);
    final pipDistance = geometry.distance(pip, palmCenter);
    if (pipDistance <= 0) return 0;

    final angle = geometry.fingerJointAngleDegrees(
      mcp: mcp,
      pip: pip,
      tip: tip,
    );

    final angleScore = _inverseLerp(145.0, 165.0, angle);
    final distanceScore = _inverseLerp(1.08, 1.22, tipDistance / pipDistance);
    final reachScore = _inverseLerp(0.25, 0.34, tipDistance / handSize);

    return (angleScore * 0.50 + distanceScore * 0.30 + reachScore * 0.20).clamp(
      0.0,
      1.0,
    );
  }

  double _thumbExtensionScore({
    required _OpenPalmLandmarks landmarks,
    required Offset palmCenter,
    required double handSize,
  }) {
    final thumbTipToPalm = geometry.distance(landmarks.thumbTip, palmCenter);
    final thumbIpToPalm = geometry.distance(landmarks.thumbIp, palmCenter);
    if (thumbIpToPalm <= 0) return 0;

    final thumbAngle = geometry.fingerJointAngleDegrees(
      mcp: landmarks.thumbMcp,
      pip: landmarks.thumbIp,
      tip: landmarks.thumbTip,
    );
    final thumbTipToIndexMcp = geometry.distanceBetweenLandmarks(
      landmarks.thumbTip,
      landmarks.indexMcp,
    );
    final thumbTipToIndexTip = geometry.distanceBetweenLandmarks(
      landmarks.thumbTip,
      landmarks.indexTip,
    );

    final angleScore = _inverseLerp(125.0, 155.0, thumbAngle);
    final tipPastIpScore = _inverseLerp(
      1.00,
      1.12,
      thumbTipToPalm / thumbIpToPalm,
    );
    final palmReachScore = _inverseLerp(0.20, 0.30, thumbTipToPalm / handSize);
    final indexMcpSeparationScore = _inverseLerp(
      0.18,
      0.30,
      thumbTipToIndexMcp / handSize,
    );
    final indexTipSeparationScore = _inverseLerp(
      0.12,
      0.24,
      thumbTipToIndexTip / handSize,
    );
    final separationScore = math.min(
      indexMcpSeparationScore,
      indexTipSeparationScore,
    );

    return (angleScore * 0.20 +
            tipPastIpScore * 0.25 +
            palmReachScore * 0.25 +
            separationScore * 0.30)
        .clamp(0.0, 1.0);
  }

  double _fingerSpreadScore({
    required _OpenPalmLandmarks landmarks,
    required double handSize,
  }) {
    final tipSpread = geometry.distanceBetweenLandmarks(
      landmarks.indexTip,
      landmarks.pinkyTip,
    );
    final mcpSpread = geometry.distanceBetweenLandmarks(
      landmarks.indexMcp,
      landmarks.pinkyMcp,
    );
    if (mcpSpread <= 0) return 0;

    final adjacentTipDistances = [
      geometry.distanceBetweenLandmarks(
        landmarks.indexTip,
        landmarks.middleTip,
      ),
      geometry.distanceBetweenLandmarks(landmarks.middleTip, landmarks.ringTip),
      geometry.distanceBetweenLandmarks(landmarks.ringTip, landmarks.pinkyTip),
    ];

    final tipSpreadScore = _inverseLerp(0.24, 0.38, tipSpread / handSize);
    final fanScore = _inverseLerp(0.85, 1.15, tipSpread / mcpSpread);
    final adjacentSpreadScore = _inverseLerp(
      0.055,
      0.12,
      geometry.average(adjacentTipDistances) / handSize,
    );

    return (tipSpreadScore * 0.45 +
            fanScore * 0.30 +
            adjacentSpreadScore * 0.25)
        .clamp(0.0, 1.0);
  }

  double _palmSideScore({
    required Hand hand,
    required _OpenPalmLandmarks landmarks,
    required bool isFrontCamera,
  }) {
    final handedness = hand.handedness;
    if (handedness == null) {
      return HandGestureThresholds.openPalmMinPalmSideConfidence;
    }

    var expectedPalmSide = handedness == Handedness.right ? 1.0 : -1.0;
    if (isFrontCamera) {
      expectedPalmSide *= -1;
    }

    final knuckleSide = _normalizedCross(
      origin: landmarks.wrist,
      first: landmarks.indexMcp,
      second: landmarks.pinkyMcp,
    );
    final thumbSide = _normalizedCross(
      origin: landmarks.indexMcp,
      first: landmarks.pinkyMcp,
      second: landmarks.thumbTip,
    );

    final knuckleScore = _inverseLerp(
      0.10,
      0.35,
      knuckleSide * expectedPalmSide,
    );
    final thumbSideScore = _inverseLerp(
      0.08,
      0.25,
      thumbSide * expectedPalmSide,
    );

    return (knuckleScore * 0.75 + thumbSideScore * 0.25).clamp(0.0, 1.0);
  }

  double _fingerYAxisScore(_OpenPalmLandmarks landmarks) {
    final scores = [
      _singleFingerYAxisScore(mcp: landmarks.indexMcp, tip: landmarks.indexTip),
      _singleFingerYAxisScore(
        mcp: landmarks.middleMcp,
        tip: landmarks.middleTip,
      ),
      _singleFingerYAxisScore(mcp: landmarks.ringMcp, tip: landmarks.ringTip),
      _singleFingerYAxisScore(mcp: landmarks.pinkyMcp, tip: landmarks.pinkyTip),
    ];

    return scores.reduce(math.min);
  }

  double _singleFingerYAxisScore({
    required HandLandmark mcp,
    required HandLandmark tip,
  }) {
    final dx = (tip.x - mcp.x).abs();
    final dy = (tip.y - mcp.y).abs();
    final length = math.sqrt(dx * dx + dy * dy);
    if (length <= 0) return 0;

    final horizontalRatio = dx / length;
    return (1 - _inverseLerp(0.35, 0.65, horizontalRatio)).clamp(0.0, 1.0);
  }

  void _trimSamples(DateTime now) {
    while (_samples.length >
        HandGestureThresholds.openPalmSmoothingSampleCount) {
      _samples.removeFirst();
    }

    while (_samples.isNotEmpty &&
        now.difference(_samples.first.time) >
            HandGestureThresholds.openPalmSmoothingMaxAge) {
      _samples.removeFirst();
    }
  }

  double _handSize(Hand hand) {
    final box = hand.boundingBox;
    final handWidth = (box.right - box.left).abs();
    final handHeight = (box.bottom - box.top).abs();
    return math.max(handWidth, handHeight);
  }

  double _normalizedCross({
    required HandLandmark origin,
    required HandLandmark first,
    required HandLandmark second,
  }) {
    final firstDx = first.x - origin.x;
    final firstDy = first.y - origin.y;
    final secondDx = second.x - origin.x;
    final secondDy = second.y - origin.y;

    final firstLength = math.sqrt(firstDx * firstDx + firstDy * firstDy);
    final secondLength = math.sqrt(secondDx * secondDx + secondDy * secondDy);
    if (firstLength <= 0 || secondLength <= 0) return 0;

    return (firstDx * secondDy - firstDy * secondDx) /
        (firstLength * secondLength);
  }

  double _inverseLerp(double min, double max, double value) {
    if (max <= min) return value >= max ? 1 : 0;
    return ((value - min) / (max - min)).clamp(0.0, 1.0);
  }
}

class _OpenPalmSample {
  const _OpenPalmSample({required this.isDetected, required this.time});

  final bool isDetected;
  final DateTime time;
}

class _OpenPalmLandmarks {
  const _OpenPalmLandmarks({
    required this.wrist,
    required this.thumbTip,
    required this.thumbIp,
    required this.thumbMcp,
    required this.indexTip,
    required this.indexPip,
    required this.indexMcp,
    required this.middleTip,
    required this.middlePip,
    required this.middleMcp,
    required this.ringTip,
    required this.ringPip,
    required this.ringMcp,
    required this.pinkyTip,
    required this.pinkyPip,
    required this.pinkyMcp,
  });

  final HandLandmark wrist;
  final HandLandmark thumbTip;
  final HandLandmark thumbIp;
  final HandLandmark thumbMcp;
  final HandLandmark indexTip;
  final HandLandmark indexPip;
  final HandLandmark indexMcp;
  final HandLandmark middleTip;
  final HandLandmark middlePip;
  final HandLandmark middleMcp;
  final HandLandmark ringTip;
  final HandLandmark ringPip;
  final HandLandmark ringMcp;
  final HandLandmark pinkyTip;
  final HandLandmark pinkyPip;
  final HandLandmark pinkyMcp;

  static _OpenPalmLandmarks? fromHand(Hand hand, HandGeometryService geometry) {
    final wrist = geometry.visibleLandmark(hand, HandLandmarkType.wrist);

    final thumbTip = geometry.visibleLandmark(hand, HandLandmarkType.thumbTip);
    final thumbIp = geometry.visibleLandmark(hand, HandLandmarkType.thumbIP);
    final thumbMcp = geometry.visibleLandmark(hand, HandLandmarkType.thumbMCP);

    final indexTip = geometry.visibleLandmark(
      hand,
      HandLandmarkType.indexFingerTip,
    );
    final indexPip = geometry.visibleLandmark(
      hand,
      HandLandmarkType.indexFingerPIP,
    );
    final indexMcp = geometry.visibleLandmark(
      hand,
      HandLandmarkType.indexFingerMCP,
    );

    final middleTip = geometry.visibleLandmark(
      hand,
      HandLandmarkType.middleFingerTip,
    );
    final middlePip = geometry.visibleLandmark(
      hand,
      HandLandmarkType.middleFingerPIP,
    );
    final middleMcp = geometry.visibleLandmark(
      hand,
      HandLandmarkType.middleFingerMCP,
    );

    final ringTip = geometry.visibleLandmark(
      hand,
      HandLandmarkType.ringFingerTip,
    );
    final ringPip = geometry.visibleLandmark(
      hand,
      HandLandmarkType.ringFingerPIP,
    );
    final ringMcp = geometry.visibleLandmark(
      hand,
      HandLandmarkType.ringFingerMCP,
    );

    final pinkyTip = geometry.visibleLandmark(hand, HandLandmarkType.pinkyTip);
    final pinkyPip = geometry.visibleLandmark(hand, HandLandmarkType.pinkyPIP);
    final pinkyMcp = geometry.visibleLandmark(hand, HandLandmarkType.pinkyMCP);

    if (wrist == null ||
        thumbTip == null ||
        thumbIp == null ||
        thumbMcp == null ||
        indexTip == null ||
        indexPip == null ||
        indexMcp == null ||
        middleTip == null ||
        middlePip == null ||
        middleMcp == null ||
        ringTip == null ||
        ringPip == null ||
        ringMcp == null ||
        pinkyTip == null ||
        pinkyPip == null ||
        pinkyMcp == null) {
      return null;
    }

    return _OpenPalmLandmarks(
      wrist: wrist,
      thumbTip: thumbTip,
      thumbIp: thumbIp,
      thumbMcp: thumbMcp,
      indexTip: indexTip,
      indexPip: indexPip,
      indexMcp: indexMcp,
      middleTip: middleTip,
      middlePip: middlePip,
      middleMcp: middleMcp,
      ringTip: ringTip,
      ringPip: ringPip,
      ringMcp: ringMcp,
      pinkyTip: pinkyTip,
      pinkyPip: pinkyPip,
      pinkyMcp: pinkyMcp,
    );
  }
}
