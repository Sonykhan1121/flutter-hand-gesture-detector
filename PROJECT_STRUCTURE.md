# Project Structure

This Flutter app is organized around one feature: smart stand control through
camera-based hand gestures.

## Quick Map

- `lib/main.dart`
  - App entry point and `MaterialApp` setup.
  - Opens the stand-control home page.

- `lib/utils/`
  - App-wide helpers that are not specific to hand gestures.
  - `app_snack_bar.dart` owns the shared snackbar style.

- `lib/hand_gesture_features/stand_control_home_page.dart`
  - Home screen for choosing the stand control mode.

- `lib/hand_gesture_features/domain/`
  - Gesture rules, thresholds, state machines, enums, and plain result models.
  - Change detection behavior here before changing UI code.

- `lib/hand_gesture_features/data/`
  - Package/API creation details.
  - `factories/hand_detector_factory.dart` configures the `hand_detection`
    detector.

- `lib/hand_gesture_features/presentation/`
  - Flutter UI, camera screen, widgets, painters, and label mapping.

## Gesture Domain Files

- `domain/constants/hand_gesture_thresholds.dart`
  - Tunable confidence, duration, distance, zoom, and recording thresholds.

- `domain/services/hand_geometry_service.dart`
  - Shared math utilities for landmarks, finger extension/fold checks, angles,
    distances, convex hulls, and polygon checks.

- `domain/services/custom_gesture_detector.dart`
  - Custom gestures:
    - Return to main position
    - Start record video
    - Detect my face
    - Pause video

- `domain/services/direction_gesture_detector.dart`
  - Left, right, up, and down hand-movement gestures.

- `domain/services/follow_object_sequence_detector.dart`
  - Open palm hold, closed fist, final open palm sequence for follow-object mode.

- `domain/services/zoom_gesture_detector.dart`
  - Thumb/index zoom-in and zoom-out gesture state machine.

## Live Camera Screen Files

The public screen import remains:

`lib/hand_gesture_features/presentation/screens/admin_hand_gesture_live_screen.dart`

That file now contains the screen class, shared state fields, lifecycle
overrides, and the one-line build entry. The implementation details are split
into same-library part files:

- `presentation/screens/admin_hand_gesture_live_screen_parts/camera_lifecycle.dart`
  - Camera permission, camera loading/failure state, camera initialization,
    stream start/stop, switching front/back cameras, cleanup, and snackbars.

- `presentation/screens/admin_hand_gesture_live_screen_parts/zoom_controls.dart`
  - Camera zoom levels, gesture zoom handling, manual zoom overlay visibility,
    slider callbacks, and zoom reset.

- `presentation/screens/admin_hand_gesture_live_screen_parts/recording_controls.dart`
  - Recording gesture holds, start/pause/resume/stop recording, recording timer,
    recording orientation handling, saving Android recordings to Downloads, and
    recording overlay buttons.

- `presentation/screens/admin_hand_gesture_live_screen_parts/gesture_processing.dart`
  - Camera frame processing, hand detection, gesture priority, follow-object
    tracking, selected hand tracking, and camera focus/exposure updates.

- `presentation/screens/admin_hand_gesture_live_screen_parts/live_screen_ui.dart`
  - Camera preview layout, recording transition scrim, main live-screen build,
    overlays, and painter selection.

## Presentation Support Files

- `presentation/widgets/`
  - Reusable Flutter widgets:
    - Home cards and hero widgets
    - Camera loading view
    - Gesture status panel
    - Round icon buttons
    - Zoom control overlay

- `presentation/painters/`
  - Custom painters for:
    - Mobile stand illustration
    - Hand landmark overlay
    - Recording hand landmark overlay
    - Follow-focus hand box overlay

- `presentation/utils/hand_gesture_label_mapper.dart`
  - Display labels for package gesture and handedness values.

## Platform Files

- `android/app/src/main/AndroidManifest.xml`
  - Android camera permission and launcher activity.

- `android/app/build.gradle.kts`
  - Android package ID, SDK versions, signing setup, shrinking, and NDK version.

- `ios/Runner/Info.plist`
  - iOS app metadata and camera permission text.

- `check_16kb_support.command`
  - Helper script for checking Android APK/AAB 16 KB page-size support.

## Common Changes

- Add or tune gesture thresholds:
  - `domain/constants/hand_gesture_thresholds.dart`

- Change gesture detection logic:
  - `domain/services/*_detector.dart`

- Change live camera behavior:
  - `presentation/screens/admin_hand_gesture_live_screen_parts/`

- Change recording controls:
  - `presentation/screens/admin_hand_gesture_live_screen_parts/recording_controls.dart`

- Change camera switching or permissions:
  - `presentation/screens/admin_hand_gesture_live_screen_parts/camera_lifecycle.dart`

- Change live screen layout:
  - `presentation/screens/admin_hand_gesture_live_screen_parts/live_screen_ui.dart`

- Change reusable visual components:
  - `presentation/widgets/`
  - `presentation/painters/`

## Verification

Use the pinned FVM Flutter toolchain:

```sh
fvm flutter analyze
fvm flutter test
```
