import 'dart:ui';

import 'package:hand_detection/hand_detection.dart';

import '../constants/hand_gesture_thresholds.dart';
import '../enums/follow_object_release_reason.dart';
import '../enums/follow_object_sequence_phase.dart';
import '../models/follow_object_sequence_result.dart';
import 'hand_geometry_service.dart';
import 'open_palm_gesture_detector.dart';

/// Gesture-only state machine for palm → fist → index point → final palm.
///
/// Target identity and the 500ms target dwell are deliberately owned by the
/// presentation-side pointing dwell controller. This detector proves only the
/// hand-pose order and exposes landmark 8 while the index-only pose is valid.
class FollowObjectSequenceDetector {
  FollowObjectSequenceDetector({
    OpenPalmGestureDetector? openPalmGestureDetector,
    HandGeometryService geometry = const HandGeometryService(),
    this.onDebug,
  }) : _openPalmGestureDetector =
           openPalmGestureDetector ?? OpenPalmGestureDetector(),
       _geometry = geometry;

  final OpenPalmGestureDetector _openPalmGestureDetector;
  final HandGeometryService _geometry;
  final void Function(String message)? onDebug;

  FollowObjectSequencePhase _phase = FollowObjectSequencePhase.idle;
  FollowObjectSequencePhase? _phaseBeforeHandLoss;
  DateTime? _lastDetectedAt;
  DateTime? _firstOpenPalmStartedAt;
  DateTime? _handMissingStartedAt;
  DateTime? _handReturnDeadline;
  DateTime? _finalPalmDeadline;
  GestureType? _currentPackageGestureType;
  double _currentGestureConfidence = 0;

  bool? _lastOpenPalmDebugValue;
  bool? _lastClosedFistDebugValue;
  bool? _lastIndexOnlyDebugValue;

  FollowObjectSequencePhase get debugPhase => _phase;
  bool? get debugOpenPalm => _lastOpenPalmDebugValue;
  bool? get debugClosedFist => _lastClosedFistDebugValue;
  bool? get debugIndexOnly => _lastIndexOnlyDebugValue;

  /// Retained for the debug evaluator API; relaxed-finger release was removed.
  int get debugRelaxedReleaseFrames => 0;

  bool get isTargetSelectionActive => _isTargetSelectionActive;
  bool get isWaitingForPoint =>
      _phase == FollowObjectSequencePhase.waitingForPoint ||
      _phase == FollowObjectSequencePhase.holdingPoint;
  bool get isWaitingForFinalPalm =>
      _phase == FollowObjectSequencePhase.waitingForFinalPalm;
  DateTime? get finalPalmDeadline => _finalPalmDeadline;

  double debugFirstOpenHoldProgress(DateTime now) {
    final startedAt = _firstOpenPalmStartedAt;
    if (startedAt == null || now.isBefore(startedAt)) return 0;
    final duration = HandGestureThresholds
        .followObjectFirstOpenPalmHoldDuration
        .inMilliseconds;
    if (duration <= 0) return 1;
    return (now.difference(startedAt).inMilliseconds / duration)
        .clamp(0.0, 1.0)
        .toDouble();
  }

  double debugHandReturnProgress(DateTime now) => _handReturnProgress(now);
  double debugFinalPalmProgress(DateTime now) => _finalPalmProgress(now);

  /// Marks that landmark 8 is dwelling inside a valid target.
  void markPointHoldStarted() {
    if (_phase == FollowObjectSequencePhase.waitingForPoint) {
      _setPhase(
        FollowObjectSequencePhase.holdingPoint,
        'index fingertip entered a target; holding for 500ms',
      );
    }
  }

  /// Resets only the target dwell while leaving the armed sequence alive.
  void markPointHoldReset() {
    if (_phase == FollowObjectSequencePhase.holdingPoint) {
      _setPhase(
        FollowObjectSequencePhase.waitingForPoint,
        'pointing dwell reset; waiting for an index-only point',
      );
    }
  }

  /// Freezes the selected target and starts the explicit final-palm phase.
  bool markPointHoldComplete({required DateTime confirmationDeadline}) {
    if (!isWaitingForPoint) return false;
    _finalPalmDeadline = confirmationDeadline;
    _setPhase(
      FollowObjectSequencePhase.waitingForFinalPalm,
      'pointing dwell complete; waiting for final open palm',
    );
    return true;
  }

  FollowObjectSequenceResult update(
    Hand hand,
    DateTime now, {
    required bool mirrorHorizontally,
    bool allowOppositePalmSide = false,
  }) {
    if (_recentDetected(now)) {
      return _result(now, isDetected: true);
    }

    if (!_geometry.isReliableHand(hand)) {
      return handleHandMissing(now);
    }

    final openPalm = _isOpenPalmGesture(
      hand: hand,
      now: now,
      mirrorHorizontally: mirrorHorizontally,
      allowOppositePalmSide: allowOppositePalmSide,
    );
    final closedFist = _isPackageGesture(
      hand: hand,
      type: GestureType.closedFist,
      debugLabel: 'closedFist',
    );
    final indexGeometry = openPalm || closedFist
        ? null
        : _indexOnlyPointingGeometry(hand);
    final indexOnly = indexGeometry != null;
    _debugPoseChange(
      openPalm: openPalm,
      closedFist: closedFist,
      indexOnly: indexOnly,
    );

    if (_phase == FollowObjectSequencePhase.waitingForHandReturn) {
      return _handleReliableHandReturn(
        now: now,
        openPalm: openPalm,
        closedFist: closedFist,
        indexGeometry: indexGeometry,
      );
    }

    if (_phase == FollowObjectSequencePhase.waitingForFinalPalm &&
        _finalPalmDeadline != null &&
        now.isAfter(_finalPalmDeadline!)) {
      return _cancelledResult(now, 'Final palm timed out');
    }

    switch (_phase) {
      case FollowObjectSequencePhase.idle:
        if (openPalm) {
          _firstOpenPalmStartedAt = now;
          _setPhase(
            FollowObjectSequencePhase.holdingFirstOpen,
            'first open palm detected; hold for 1 second',
          );
        }
        break;

      case FollowObjectSequencePhase.holdingFirstOpen:
        if (!openPalm) {
          _debug('first open palm interrupted; reset sequence');
          clear();
          break;
        }
        final startedAt = _firstOpenPalmStartedAt;
        if (startedAt != null &&
            now.difference(startedAt) >=
                HandGestureThresholds.followObjectFirstOpenPalmHoldDuration) {
          _setPhase(
            FollowObjectSequencePhase.waitingForClosed,
            'first open palm complete; waiting for closed fist',
          );
        }
        break;

      case FollowObjectSequencePhase.waitingForClosed:
        if (closedFist) {
          _setPhase(
            FollowObjectSequencePhase.waitingForPoint,
            'closed fist detected; move then point with index only',
          );
        }
        break;

      case FollowObjectSequencePhase.waitingForPoint:
      case FollowObjectSequencePhase.holdingPoint:
        // Candidate dwell is updated outside this gesture-only detector.
        // Any non-index pose resets that dwell but does not disarm the sequence.
        if (!indexOnly && _phase == FollowObjectSequencePhase.holdingPoint) {
          markPointHoldReset();
        }
        break;

      case FollowObjectSequencePhase.waitingForFinalPalm:
        if (openPalm) {
          final packageGestureType = _currentPackageGestureType;
          final gestureConfidence = _currentGestureConfidence;
          _lastDetectedAt = now;
          clear(keepLastDetected: true);
          return FollowObjectSequenceResult(
            isActive: true,
            isDetected: true,
            isTargetSelectionActive: false,
            packageGestureType: packageGestureType,
            gestureConfidence: gestureConfidence,
            releaseReason: FollowObjectReleaseReason.openPalm,
            isFinalPalmConfirmation: true,
          );
        }
        break;

      case FollowObjectSequencePhase.waitingForHandReturn:
        // Hand-return handling occurs before the switch.
        break;
    }

    return _result(
      now,
      indexPip: isWaitingForPoint ? indexGeometry?.pip : null,
      indexTip: isWaitingForPoint ? indexGeometry?.tip : null,
      isIndexOnlyPointing: isWaitingForPoint && indexOnly,
    );
  }

  /// Starts or advances the two-second hand-return grace without auto-release.
  FollowObjectSequenceResult handleHandMissing(DateTime now) {
    if (!_isTargetSelectionActive) {
      if (_phase != FollowObjectSequencePhase.idle) clear();
      return const FollowObjectSequenceResult(
        isActive: false,
        isDetected: false,
        isTargetSelectionActive: false,
      );
    }

    if (_phase != FollowObjectSequencePhase.waitingForHandReturn) {
      _openPalmGestureDetector.clear();
      _phaseBeforeHandLoss =
          _phase == FollowObjectSequencePhase.waitingForFinalPalm
          ? FollowObjectSequencePhase.waitingForFinalPalm
          : FollowObjectSequencePhase.waitingForPoint;
      _handMissingStartedAt = now;
      final graceDeadline = now.add(
        HandGestureThresholds.followObjectHandReturnGraceDuration,
      );
      final finalDeadline = _finalPalmDeadline;
      _handReturnDeadline =
          finalDeadline != null && finalDeadline.isBefore(graceDeadline)
          ? finalDeadline
          : graceDeadline;
      _setPhase(
        FollowObjectSequencePhase.waitingForHandReturn,
        'hand lost; wait up to two seconds, then cancel',
      );
    }

    final deadline = _handReturnDeadline;
    if (deadline != null && now.isAfter(deadline)) {
      return _cancelledResult(now, 'Hand did not return in time');
    }
    return _result(now);
  }

  /// Backward-compatible name; hand loss now cancels instead of auto-selecting.
  FollowObjectSequenceResult releaseFromLastVisiblePoint(DateTime now) =>
      handleHandMissing(now);

  void clear({bool keepLastDetected = false}) {
    if (_phase != FollowObjectSequencePhase.idle) {
      _debug(
        'clear sequence | keepLastDetected=$keepLastDetected, '
        'previousPhase=${_phase.name}',
      );
    }
    _phase = FollowObjectSequencePhase.idle;
    _phaseBeforeHandLoss = null;
    _firstOpenPalmStartedAt = null;
    _handMissingStartedAt = null;
    _handReturnDeadline = null;
    _finalPalmDeadline = null;
    _currentPackageGestureType = null;
    _currentGestureConfidence = 0;
    _lastOpenPalmDebugValue = null;
    _lastClosedFistDebugValue = null;
    _lastIndexOnlyDebugValue = null;
    _openPalmGestureDetector.clear();
    if (!keepLastDetected) _lastDetectedAt = null;
  }

  FollowObjectSequenceResult _handleReliableHandReturn({
    required DateTime now,
    required bool openPalm,
    required bool closedFist,
    required _IndexPointingGeometry? indexGeometry,
  }) {
    final returnDeadline = _handReturnDeadline;
    if (returnDeadline != null && now.isAfter(returnDeadline)) {
      return _cancelledResult(now, 'Hand did not return in time');
    }

    final previousPhase = _phaseBeforeHandLoss;
    if (previousPhase == FollowObjectSequencePhase.waitingForFinalPalm) {
      final finalDeadline = _finalPalmDeadline;
      if (finalDeadline != null && now.isAfter(finalDeadline)) {
        return _cancelledResult(now, 'Final palm timed out');
      }
      if (openPalm) {
        final packageGestureType = _currentPackageGestureType;
        final gestureConfidence = _currentGestureConfidence;
        _lastDetectedAt = now;
        clear(keepLastDetected: true);
        return FollowObjectSequenceResult(
          isActive: true,
          isDetected: true,
          isTargetSelectionActive: false,
          packageGestureType: packageGestureType,
          gestureConfidence: gestureConfidence,
          releaseReason: FollowObjectReleaseReason.openPalm,
          isFinalPalmConfirmation: true,
        );
      }
      return _result(now);
    }

    if (closedFist || indexGeometry != null) {
      _phaseBeforeHandLoss = null;
      _handMissingStartedAt = null;
      _handReturnDeadline = null;
      _setPhase(
        FollowObjectSequencePhase.waitingForPoint,
        'hand returned; waiting for index-only target point',
      );
      return _result(
        now,
        indexPip: indexGeometry?.pip,
        indexTip: indexGeometry?.tip,
        isIndexOnlyPointing: indexGeometry != null,
      );
    }
    return _result(now);
  }

  FollowObjectSequenceResult _cancelledResult(DateTime now, String reason) {
    _debug('sequence cancelled: $reason');
    clear();
    return FollowObjectSequenceResult(
      isActive: false,
      isDetected: false,
      isTargetSelectionActive: false,
      wasCancelled: true,
      cancellationReason: reason,
    );
  }

  FollowObjectSequenceResult _result(
    DateTime now, {
    bool isDetected = false,
    Offset? indexPip,
    Offset? indexTip,
    bool isIndexOnlyPointing = false,
  }) {
    final detected = isDetected || _recentDetected(now);
    return FollowObjectSequenceResult(
      isActive: _phase != FollowObjectSequencePhase.idle || detected,
      isDetected: detected,
      isTargetSelectionActive: _isTargetSelectionActive,
      packageGestureType: _currentPackageGestureType,
      gestureConfidence: _currentGestureConfidence,
      isWaitingForHandReturn:
          _phase == FollowObjectSequencePhase.waitingForHandReturn,
      handReturnDeadline: _handReturnDeadline,
      handReturnProgress: _handReturnProgress(now),
      indexPip: indexPip,
      indexTip: indexTip,
      isIndexOnlyPointing: isIndexOnlyPointing,
      isWaitingForFinalPalm:
          _phase == FollowObjectSequencePhase.waitingForFinalPalm ||
          (_phase == FollowObjectSequencePhase.waitingForHandReturn &&
              _phaseBeforeHandLoss ==
                  FollowObjectSequencePhase.waitingForFinalPalm),
      finalPalmDeadline: _finalPalmDeadline,
      finalPalmProgress: _finalPalmProgress(now),
    );
  }

  bool get _isTargetSelectionActive =>
      _phase == FollowObjectSequencePhase.waitingForPoint ||
      _phase == FollowObjectSequencePhase.holdingPoint ||
      _phase == FollowObjectSequencePhase.waitingForFinalPalm ||
      _phase == FollowObjectSequencePhase.waitingForHandReturn;

  _IndexPointingGeometry? _indexOnlyPointingGeometry(Hand hand) {
    if (_geometry.isReliablePackageGesture(
      hand.gesture,
      type: GestureType.victory,
    )) {
      return null;
    }

    final palmCenter = _geometry.palmCenter3D(hand);
    final handSize = _geometry.handSizeFromBoundingBox(hand.boundingBox);
    if (palmCenter == null || handSize <= 0) return null;

    final indexChain = _geometry.visibleFingerChain(
      hand,
      HandGestureThresholds.directionFingerChainTypes.first,
    );
    if (indexChain == null ||
        !_geometry.isFingerExtendedByAngle3D(
          mcp: indexChain[0],
          pip: indexChain[1],
          tip: indexChain[3],
          palmCenter: palmCenter,
          handSize: handSize,
        )) {
      return null;
    }

    for (final chainTypes
        in HandGestureThresholds.directionFingerChainTypes.skip(1)) {
      final chain = _geometry.visibleFingerChain(hand, chainTypes);
      if (chain == null ||
          !_geometry.isFingerChainFolded3D(
            chain: chain,
            palmCenter: palmCenter,
            handSize: handSize,
          )) {
        return null;
      }
    }

    final thumbIp = _geometry.visibleLandmark(hand, HandLandmarkType.thumbIP);
    final thumbTip = _geometry.visibleLandmark(hand, HandLandmarkType.thumbTip);
    if (thumbIp == null ||
        thumbTip == null ||
        !_geometry.isFingerFolded3D(
          tip: thumbTip,
          pip: thumbIp,
          palmCenter: palmCenter,
          handSize: handSize,
        ) ||
        _geometry.distanceToPoint3D(thumbTip, palmCenter) >
            handSize *
                HandGestureThresholds.followObjectPointingThumbMaxReachRatio) {
      return null;
    }

    final pip = indexChain[1];
    final tip = indexChain[3];
    return _IndexPointingGeometry(
      pip: Offset(pip.x, pip.y),
      tip: Offset(tip.x, tip.y),
    );
  }

  bool _isOpenPalmGesture({
    required Hand hand,
    required DateTime now,
    required bool mirrorHorizontally,
    required bool allowOppositePalmSide,
  }) {
    final detection = _openPalmGestureDetector.detect(
      hand: hand,
      now: now,
      mirrorHorizontally: mirrorHorizontally,
      allowOppositePalmSide: allowOppositePalmSide,
    );
    if (detection.isDetected) {
      _currentPackageGestureType = GestureType.openPalm;
      _currentGestureConfidence = detection.confidence;
    }
    return detection.isDetected;
  }

  bool _isPackageGesture({
    required Hand hand,
    required GestureType type,
    required String debugLabel,
  }) {
    final gesture = hand.gesture;
    if (gesture == null ||
        !_geometry.isReliablePackageGesture(gesture, type: type)) {
      return false;
    }
    if (type == GestureType.closedFist &&
        _geometry.matchesPunchMiddleFingerCircle(hand)) {
      _debug('package $debugLabel belongs to compact Punch circle');
      return false;
    }
    _currentPackageGestureType = gesture.type;
    _currentGestureConfidence = gesture.confidence;
    return true;
  }

  bool _recentDetected(DateTime now) {
    final lastDetectedAt = _lastDetectedAt;
    return lastDetectedAt != null &&
        now.difference(lastDetectedAt) <=
            HandGestureThresholds.followObjectMessageHoldDuration;
  }

  double _handReturnProgress(DateTime now) {
    final startedAt = _handMissingStartedAt;
    final deadline = _handReturnDeadline;
    if (startedAt == null || deadline == null || now.isBefore(startedAt)) {
      return 0;
    }
    final total = deadline.difference(startedAt).inMilliseconds;
    if (total <= 0) return 1;
    return (now.difference(startedAt).inMilliseconds / total)
        .clamp(0.0, 1.0)
        .toDouble();
  }

  double _finalPalmProgress(DateTime now) {
    final deadline = _finalPalmDeadline;
    if (deadline == null) return 0;
    final duration = HandGestureThresholds
        .followObjectFinalPalmConfirmationDuration
        .inMilliseconds;
    if (duration <= 0) return 1;
    final startedAt = deadline.subtract(
      HandGestureThresholds.followObjectFinalPalmConfirmationDuration,
    );
    if (now.isBefore(startedAt)) return 0;
    return (now.difference(startedAt).inMilliseconds / duration)
        .clamp(0.0, 1.0)
        .toDouble();
  }

  void _debugPoseChange({
    required bool openPalm,
    required bool closedFist,
    required bool indexOnly,
  }) {
    if (_lastOpenPalmDebugValue == openPalm &&
        _lastClosedFistDebugValue == closedFist &&
        _lastIndexOnlyDebugValue == indexOnly) {
      return;
    }
    _lastOpenPalmDebugValue = openPalm;
    _lastClosedFistDebugValue = closedFist;
    _lastIndexOnlyDebugValue = indexOnly;
    _debug(
      'pose | phase=${_phase.name}, palm=$openPalm, '
      'fist=$closedFist, indexOnly=$indexOnly',
    );
  }

  void _setPhase(FollowObjectSequencePhase phase, String reason) {
    if (_phase == phase) return;
    _debug('phase ${_phase.name} -> ${phase.name} | $reason');
    _phase = phase;
  }

  void _debug(String message) => onDebug?.call('[FollowObject] $message');
}

class _IndexPointingGeometry {
  const _IndexPointingGeometry({required this.pip, required this.tip});

  final Offset pip;
  final Offset tip;
}
