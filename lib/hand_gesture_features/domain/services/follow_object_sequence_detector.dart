import 'dart:ui';

import 'package:hand_detection/hand_detection.dart';

import '../constants/hand_gesture_thresholds.dart';
import '../enums/follow_object_sequence_phase.dart';
import '../models/follow_object_sequence_result.dart';
import 'open_palm_gesture_detector.dart';

class FollowObjectSequenceDetector {
  FollowObjectSequenceDetector({
    OpenPalmGestureDetector? openPalmGestureDetector,
    this.onDebug,
  }) : _openPalmGestureDetector =
           openPalmGestureDetector ?? OpenPalmGestureDetector();

  final OpenPalmGestureDetector _openPalmGestureDetector;
  final void Function(String message)? onDebug;

  FollowObjectSequencePhase _phase = FollowObjectSequencePhase.idle;
  DateTime? _lastDetectedAt;
  DateTime? _firstOpenPalmStartedAt;
  GestureType? _currentPackageGestureType;

  bool? _lastOpenPalmDebugValue;
  bool? _lastClosedFistDebugValue;

  /// V1.0.3 behavior:
  ///
  /// 1. User first shows open palm and holds it for 1 second.
  /// 2. The sequence starts and stays alive while the hand remains on screen.
  /// 3. User can show closed fist any time later.
  /// 4. User can move while staying on screen.
  /// 5. User can show open palm again any time later.
  /// 6. Then this returns isDetected=true to show "Follow the object".
  ///
  /// Important: when the hand leaves the screen or becomes unreliable,
  /// the presentation layer calls [clear], so the sequence resets.
  FollowObjectSequenceResult update(
    Hand hand,
    DateTime now, {
    required bool mirrorHorizontally,
    bool allowOppositePalmSide = false,
  }) {
    if (_recentDetected(now)) {
      _debug(
        'recent detected message is still active -> show "Follow the object"',
      );

      return FollowObjectSequenceResult(
        isActive: true,
        isDetected: true,
        packageGestureType: _currentPackageGestureType,
      );
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

    _debugPoseChange(openPalm: openPalm, closedFist: closedFist);

    var detected = false;
    Offset? releasePoint;

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
          _debug('first open palm hold interrupted; reset sequence');
          clear();
          break;
        }

        final firstOpenPalmStartedAt = _firstOpenPalmStartedAt;
        if (firstOpenPalmStartedAt != null &&
            now.difference(firstOpenPalmStartedAt) >=
                HandGestureThresholds.followObjectFirstOpenPalmHoldDuration) {
          _setPhase(
            FollowObjectSequencePhase.waitingForClosed,
            'first open palm hold completed; waiting for closed fist',
          );
        }
        break;

      case FollowObjectSequencePhase.waitingForClosed:
        if (closedFist) {
          _setPhase(
            FollowObjectSequencePhase.waitingForFinalOpen,
            'closed fist detected; waiting for final open palm',
          );
        }
        break;

      case FollowObjectSequencePhase.waitingForFinalOpen:
        if (openPalm) {
          _lastDetectedAt = now;
          detected = true;
          releasePoint = _handReleasePoint(hand);
          _debug(
            'sequence completed -> release point '
            '(${releasePoint.dx.toStringAsFixed(1)}, '
            '${releasePoint.dy.toStringAsFixed(1)})',
          );
          clear(keepLastDetected: true);
        }
        break;
    }

    final isActive = _phase != FollowObjectSequencePhase.idle;
    final isDetected = detected || _recentDetected(now);

    return FollowObjectSequenceResult(
      isActive: isActive || isDetected,
      isDetected: isDetected,
      packageGestureType: _currentPackageGestureType,
      releasePoint: releasePoint,
    );
  }

  void clear({bool keepLastDetected = false}) {
    if (_phase != FollowObjectSequencePhase.idle) {
      _debug(
        'clear sequence | keepLastDetected=$keepLastDetected, '
        'previousPhase=${_phase.name}',
      );
    }

    _phase = FollowObjectSequencePhase.idle;
    _firstOpenPalmStartedAt = null;
    _currentPackageGestureType = null;
    _lastOpenPalmDebugValue = null;
    _lastClosedFistDebugValue = null;
    _openPalmGestureDetector.clear();

    if (!keepLastDetected) {
      _lastDetectedAt = null;
    }
  }

  bool _isOpenPalmGesture({
    required Hand hand,
    required DateTime now,
    required bool mirrorHorizontally,
    required bool allowOppositePalmSide,
  }) {
    final result = _openPalmGestureDetector.detect(
      hand: hand,
      now: now,
      mirrorHorizontally: mirrorHorizontally,
      allowOppositePalmSide: allowOppositePalmSide,
    );

    if (result.isDetected) {
      _currentPackageGestureType = GestureType.openPalm;
      _debug(
        'custom openPalm detected | '
        'confidence=${result.confidence.toStringAsFixed(2)}',
      );
    }

    return result.isDetected;
  }

  bool _isPackageGesture({
    required Hand hand,
    required GestureType type,
    required String debugLabel,
  }) {
    final gesture = hand.gesture;

    final detected =
        gesture != null &&
        gesture.type == type &&
        gesture.confidence >= HandGestureThresholds.minPackageGestureConfidence;

    if (detected) {
      _currentPackageGestureType = gesture.type;
      _debug(
        'package $debugLabel detected | '
        'confidence=${gesture.confidence.toStringAsFixed(2)}',
      );
    }

    return detected;
  }

  bool _recentDetected(DateTime now) {
    final lastDetectedAt = _lastDetectedAt;
    return lastDetectedAt != null &&
        now.difference(lastDetectedAt) <=
            HandGestureThresholds.followObjectMessageHoldDuration;
  }

  Offset _handReleasePoint(Hand hand) {
    final box = hand.boundingBox;
    return Offset((box.left + box.right) / 2, (box.top + box.bottom) / 2);
  }

  void _debugPoseChange({required bool openPalm, required bool closedFist}) {
    if (_lastOpenPalmDebugValue == openPalm &&
        _lastClosedFistDebugValue == closedFist) {
      return;
    }

    _lastOpenPalmDebugValue = openPalm;
    _lastClosedFistDebugValue = closedFist;

    _debug(
      'pose changed -> phase=${_phase.name}, '
      'openPalm=$openPalm, closedFist=$closedFist',
    );
  }

  void _setPhase(FollowObjectSequencePhase nextPhase, String reason) {
    if (_phase == nextPhase) return;

    _debug('phase ${_phase.name} -> ${nextPhase.name} | $reason');
    _phase = nextPhase;
  }

  void _debug(String message) {
    onDebug?.call('[FollowObjectSequence] $message');
  }
}
