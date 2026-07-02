# Smart Stand Control

Smart Stand Control is a Flutter camera app for controlling a mobile stand with hand gestures. The app reads the live camera stream, detects the user's hand, shows the current gesture on screen, and maps that gesture to camera or stand actions.

<p align="center">
  <strong>Hand gesture control</strong> · <strong>Live camera preview</strong> · <strong>Zoom</strong> · <strong>Recording</strong> · <strong>Object follow</strong>
</p>

## Gesture Action Guide

This is the full gesture sheet for the app.

<p align="center">
  <img width="520" alt="Gesture Actions For Control App" src="https://github.com/user-attachments/assets/27f87f5a-0047-4050-81b8-aac3949fd01c" />
</p>

## App Screens

| Home / Mode Selection |
| --- |
| <img src="https://github.com/user-attachments/assets/36623e0d-7cf6-4c40-a3fa-56ee0faeff45" alt="Control settings home screen" width="200" height="370" style="border: 2px solid #000; border-radius: 10px;" /> |
| Choose Automatic Detect, Hand Gesture, or Voice Command. |

## Gesture Demo Images

Replace each demo `src` with your own GitHub uploaded image URL when you have screenshots or short demo frames for that action.

| Move Left | Move Right | Move Up |
| --- | --- | --- |
| <img src="https://github.com/user-attachments/assets/2e4b3515-5f13-48f2-bb80-4d15b7f85b20" alt="Move left gesture demo" width="200" height="370" style="border: 2px solid #000; border-radius: 10px;" /> | <img src="https://github.com/user-attachments/assets/60dfc86e-77b5-44d3-8b8c-ab3cc1154076" alt="Move right gesture demo" width="200" height="370" style="border: 2px solid #000; border-radius: 10px;" /> | <img src="https://github.com/user-attachments/assets/1f37db34-16a2-41ac-b9f7-f6b9ab193377" alt="Move up gesture demo" width="200" height="370" style="border: 2px solid #000; border-radius: 10px;" /> |
| Swipe or hold the hand toward the left. | Swipe or hold the hand toward the right. | Point or move the hand upward. |

| Move Down | Detect My Face | Follow The Object |
| --- | --- | --- |
| <img src="https://github.com/user-attachments/assets/07960aca-6df4-48bf-a9f2-44144bb2716c" alt="Move down gesture demo" width="200" height="370" style="border: 2px solid #000; border-radius: 10px;" /> | <img src="https://github.com/user-attachments/assets/db63e89d-38c9-40fd-a502-b816fe1b9cfd" alt="Detect my face gesture demo" width="200" height="370" style="border: 2px solid #000; border-radius: 10px;" /> | <img src="https://github.com/user-attachments/assets/a3d40b80-2dd5-430c-b354-776421e602b9" alt="Follow the object gesture demo" width="200" height="370" style="border: 2px solid #000; border-radius: 10px;" /> |
| Point or move the hand downward. | Hold the call gesture for 2 seconds to start face detection. | Open palm, closed fist, then release on the object. |

| Stop & Continue | Return To Main Position | Start Record Video |
| --- | --- | --- |
| <img src="https://github.com/user-attachments/assets/638234dc-f41c-4e03-90eb-432e94ca4976" alt="Stop and continue gesture demo" width="200" height="370" style="border: 2px solid #000; border-radius: 10px;" /> | <img src="https://github.com/user-attachments/assets/e6ffafc7-79b7-4a9c-a9b5-1b4989f84326" alt="Return to main position gesture demo" width="200" height="370" style="border: 2px solid #000; border-radius: 10px;" /> | <img src="https://github.com/user-attachments/assets/033ba49a-8b9c-4992-b3d9-4c14b615cecf" alt="Start record video gesture demo" width="200" height="370" style="border: 2px solid #000; border-radius: 10px;" /> |
| Hold thumbs-up for 1 second. | Rotate the index finger in a small circle. | Hold the OK gesture for 1 second. |

| Pause Video | End Record Video | Zoom In |
| --- | --- | --- |
| <img src="https://github.com/user-attachments/assets/17f3c551-5a65-4bfe-bf0e-d6188aca8200" alt="Pause video gesture demo" width="200" height="370" style="border: 2px solid #000; border-radius: 10px;" /> | <img src="https://github.com/user-attachments/assets/9d00df54-69be-49c4-9f56-bed01af41c78" alt="End record video gesture demo" width="200" height="370" style="border: 2px solid #000; border-radius: 10px;" /> | <img src="https://github.com/user-attachments/assets/8082dd6e-4d67-4704-b511-2931f2181963" alt="Zoom in gesture demo" width="200" height="370" style="border: 2px solid #000; border-radius: 10px;" /> |
| Make a fist and hold for 1 second. | Hold the victory gesture for 2 seconds. | Pinch fingers together, then open outward. |

| Zoom Out |
| --- |
| <img src="https://github.com/user-attachments/assets/bd6b86df-cb8d-4bc0-b72e-7d8a2b5519cb" alt="Zoom out gesture demo" width="200" height="370" style="border: 2px solid #000; border-radius: 10px;" /> |
| Start with open fingers, then pinch together. |

## Features

| Feature | What It Does |
| --- | --- |
| Control mode screen | Lets the user choose Automatic Detect, Hand Gesture, or Voice Command. |
| Live hand detection | Detects hands, landmarks, handedness, and gesture confidence from the camera stream. |
| Direction control | Reads left, right, up, and down hand movement. |
| Face detect action | Uses the call gesture to trigger face recognition/follow behavior. |
| Object follow action | Uses palm and fist gestures to start object-follow flow. |
| Recording actions | Starts, pauses, continues, and ends video recording through hand gestures. |
| Camera zoom | Supports zoom in and zoom out gestures plus a manual zoom overlay. |
| Focus overlay | Highlights the selected hand and updates camera focus/exposure. |
| Camera switching | Supports front and back cameras. |
| Platform handling | Keeps Android and iOS camera frames, rotation, and mirror behavior aligned. |

## Gesture Actions

| Function | Gesture Details |
| --- | --- |
| Move left | Swipe your open hand from center to left. Hold the position to continue moving. |
| Move right | Swipe your open hand from center to right. Hold the position to continue moving. |
| Move up | Point the index finger upward or move the palm upward. |
| Move down | Point the index finger downward or move the palm downward. |
| Detect my face | Hold the call gesture for 2 seconds. |
| Follow the object | Hold your palm in front of the camera, make a fist, drag to the object, then release. |
| Stop & Continue action | Show thumbs-up and hold for 1 second. |
| Return to main position | Rotate your index finger in a small circle. |
| Start record video | Hold the OK gesture for 1 second. |
| Pause video | Make a fist and hold for 1 second. |
| End record video | Make a victory sign and keep it for 2 seconds. |
| Zoom in | Pinch fingers together, then open them outward. |
| Zoom out | Start with open fingers, then pinch them together. |

## GitHub Image Template

After uploading an image to a GitHub issue, pull request, or README editor, copy the generated `user-attachments` URL and paste it into the `src`.

```html
<img src="https://github.com/user-attachments/assets/YOUR_IMAGE_ID" alt="Screen name" width="200" height="370" style="border: 2px solid #000; border-radius: 10px;" />
```

GitHub may ignore inline `style`, but `width` and `height` work in README files.

## Tech Stack

| Layer | Tools |
| --- | --- |
| Framework | Flutter |
| Language | Dart |
| Camera | `camera` |
| Hand detection | `hand_detection` |
| Permissions | `permission_handler` |
| Platforms | Android and iOS |

## Project Structure

For a guided map of where each feature lives, see [`PROJECT_STRUCTURE.md`](PROJECT_STRUCTURE.md).

```text
lib/
  hand_gesture_features/
    data/factories/          Hand detector creation
    domain/constants/        Gesture thresholds
    domain/services/         Gesture detection logic
    presentation/painters/   Camera overlay and landmark painters
    presentation/screens/    Live camera screen and screen parts
    presentation/widgets/    Reusable UI components
```

## Development

This project is pinned to Flutter through FVM. Use the pinned toolchain:

```sh
fvm flutter pub get
fvm flutter analyze
fvm flutter test
```

Run the app:

```sh
fvm flutter run
```

## Platform Notes

### iOS

- Requires camera permission in `ios/Runner/Info.plist`.
- Uses `ImageFormatGroup.yuv420` for live detection frames.
- Front-camera overlay mirroring is handled separately from Android so iOS gestures and drawings stay aligned.

### Android

- Requires camera permission in `android/app/src/main/AndroidManifest.xml`.
- Uses `ImageFormatGroup.yuv420` for live detection frames.
- Preview rotation and front-camera mirroring are handled for recording and live overlays.

## Android Release Signing

Copy `android/key.properties.example` to `android/key.properties` and fill it with your local release keystore values before building a release app bundle.

Do not commit real signing secrets.
