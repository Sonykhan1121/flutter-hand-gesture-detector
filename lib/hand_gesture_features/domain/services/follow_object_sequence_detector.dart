import 'dart:math' as math;
import 'dart:ui';

import 'package:hand_detection/hand_detection.dart';

import '../constants/hand_gesture_thresholds.dart';
import '../enums/follow_object_sequence_phase.dart';
import '../enums/follow_object_release_reason.dart';
import '../models/follow_object_sequence_result.dart';
import 'hand_geometry_service.dart';
import 'open_palm_gesture_detector.dart';

/// State machine for "open palm, closed fist, release" object following.
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
  DateTime? _lastDetectedAt;
  DateTime? _firstOpenPalmStartedAt;
  Offset? _lastVisibleReleasePoint;
  GestureType? _currentPackageGestureType;
  double _currentGestureConfidence = 0;

  bool? _lastOpenPalmDebugValue;
  bool? _lastClosedFistDebugValue;

  /// V1.0.3 behavior:
  ///
  /// 1. User first shows open palm and holds it for 1 second.
  /// 2. The sequence starts and stays alive while the hand remains on screen.
  /// 3. User can show closed fist any time later.
  /// 4. Full-screen target scanning starts after the first closed fist.
  /// 5. User can move while staying on screen.
  /// 6. Final open palm or hand leaving the screen releases at the last
  ///    visible hand center.
  ///
  /// Important: once closed fist has been detected, the presentation layer can
  /// call [releaseFromLastVisiblePoint] when the hand leaves the screen.
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
        isTargetSelectionActive: false,
        packageGestureType: _currentPackageGestureType,
        gestureConfidence: _currentGestureConfidence,
      );
    }

    if (!_geometry.isReliableHand(hand)) {
      return _handleUnreliableHand();
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

    // The switch below advances only one phase at a time so every frame has a
    // predictable sequence status for the UI and target scanner.
    _debugPoseChange(openPalm: openPalm, closedFist: closedFist);

    var detected = false;
    Offset? releasePoint;
    FollowObjectReleaseReason? releaseReason;
    GestureType? packageGestureType;
    var gestureConfidence = 0.0;

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
          _lastVisibleReleasePoint = _handReleasePoint(hand);
          _setPhase(
            FollowObjectSequencePhase.waitingForFinalOpen,
            'closed fist detected; waiting for final open palm',
          );
        }
        break;

      case FollowObjectSequencePhase.waitingForFinalOpen:
        final currentReleasePoint = _handReleasePoint(hand);
        _lastVisibleReleasePoint = currentReleasePoint;

        if (openPalm) {
          _lastDetectedAt = now;
          detected = true;
          releasePoint = currentReleasePoint;
          releaseReason = FollowObjectReleaseReason.openPalm;
          packageGestureType = _currentPackageGestureType;
          gestureConfidence = _currentGestureConfidence;
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
      isTargetSelectionActive: _isTargetSelectionActive,
      packageGestureType: packageGestureType ?? _currentPackageGestureType,
      gestureConfidence: math.max(gestureConfidence, _currentGestureConfidence),
      releasePoint: releasePoint,
      releaseReason: releaseReason,
    );
  }

  /// True while the detector is waiting for final open palm or hand release.
  bool get isTargetSelectionActive => _isTargetSelectionActive;

  /// Completes the sequence from the last saved hand center after hand loss.
  FollowObjectSequenceResult releaseFromLastVisiblePoint(DateTime now) {
    if (!_isTargetSelectionActive) {
      if (_phase != FollowObjectSequencePhase.idle) {
        clear();
      }

      return const FollowObjectSequenceResult(
        isActive: false,
        isDetected: false,
        isTargetSelectionActive: false,
      );
    }

    final releasePoint = _lastVisibleReleasePoint;
    if (releasePoint == null) {
      _debug('hand lost without a saved release point; reset sequence');
      clear();

      return const FollowObjectSequenceResult(
        isActive: false,
        isDetected: false,
        isTargetSelectionActive: false,
      );
    }

    _lastDetectedAt = now;
    final packageGestureType = _currentPackageGestureType;
    final gestureConfidence = _currentGestureConfidence;
    _debug(
      'hand lost -> release from last visible point '
      '(${releasePoint.dx.toStringAsFixed(1)}, '
      '${releasePoint.dy.toStringAsFixed(1)})',
    );
    clear(keepLastDetected: true);

    return FollowObjectSequenceResult(
      isActive: true,
      isDetected: true,
      isTargetSelectionActive: false,
      packageGestureType: packageGestureType,
      gestureConfidence: gestureConfidence,
      releasePoint: releasePoint,
      releaseReason: FollowObjectReleaseReason.handLost,
    );
  }

  /// Resets phase data, optionally keeping the recent success message alive.
  void clear({bool keepLastDetected = false}) {
    if (_phase != FollowObjectSequencePhase.idle) {
      _debug(
        'clear sequence | keepLastDetected=$keepLastDetected, '
        'previousPhase=${_phase.name}',
      );
    }

    _phase = FollowObjectSequencePhase.idle;
    _firstOpenPalmStartedAt = null;
    _lastVisibleReleasePoint = null;
    _currentPackageGestureType = null;
    _currentGestureConfidence = 0;
    _lastOpenPalmDebugValue = null;
    _lastClosedFistDebugValue = null;
    _openPalmGestureDetector.clear();

    if (!keepLastDetected) {
      _lastDetectedAt = null;
    }
  }

  /// Uses the custom open-palm detector and stores the active package label.
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
      _currentGestureConfidence = result.confidence;
      _debug(
        'custom openPalm detected | '
        'confidence=${result.confidence.toStringAsFixed(2)}',
      );
    }

    return result.isDetected;
  }

  /// Checks a package gesture type against the shared confidence threshold.
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

    _currentPackageGestureType = gesture.type;
    _currentGestureConfidence = gesture.confidence;
    _debug(
      'package $debugLabel detected | '
      'confidence=${gesture.confidence.toStringAsFixed(2)}',
    );

    return true;
  }

  /// Holds a completed sequence result long enough for the UI to show it.
  bool _recentDetected(DateTime now) {
    final lastDetectedAt = _lastDetectedAt;
    return lastDetectedAt != null &&
        now.difference(lastDetectedAt) <=
            HandGestureThresholds.followObjectMessageHoldDuration;
  }

  /// Internal check for the target-selection phase.
  bool get _isTargetSelectionActive =>
      _phase == FollowObjectSequencePhase.waitingForFinalOpen;

  FollowObjectSequenceResult _handleUnreliableHand() {
    _openPalmGestureDetector.clear();

    if (_isTargetSelectionActive) {
      _debug('unreliable hand while selecting target; keep last release point');
      return FollowObjectSequenceResult(
        isActive: true,
        isDetected: false,
        isTargetSelectionActive: true,
        packageGestureType: _currentPackageGestureType,
        gestureConfidence: _currentGestureConfidence,
      );
    }

    if (_phase != FollowObjectSequencePhase.idle) {
      _debug('unreliable hand interrupted sequence; reset');
      clear();
    }

    return const FollowObjectSequenceResult(
      isActive: false,
      isDetected: false,
      isTargetSelectionActive: false,
    );
  }

  /// Uses the hand bounding-box center as the target release point.
  Offset _handReleasePoint(Hand hand) {
    final box = hand.boundingBox;
    return Offset((box.left + box.right) / 2, (box.top + box.bottom) / 2);
  }

  /// Prints debug output only when open-palm or fist pose state changes.
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

  /// Moves to a new sequence phase and logs the reason.
  void _setPhase(FollowObjectSequencePhase nextPhase, String reason) {
    if (_phase == nextPhase) return;

    _debug('phase ${_phase.name} -> ${nextPhase.name} | $reason');
    _phase = nextPhase;
  }

  /// Sends namespaced debug messages when a listener is attached.
  void _debug(String message) {
    onDebug?.call('[FollowObjectSequence] $message');
  }
}
