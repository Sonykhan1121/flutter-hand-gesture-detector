# Smart Stand Control

A Flutter app for controlling a smart mobile stand with camera-based hand gesture detection.

## Development

This project is pinned to Flutter through FVM. Use the pinned toolchain:

```sh
fvm flutter pub get
fvm flutter analyze
fvm flutter test
```

## Android Release Signing

Copy `android/key.properties.example` to `android/key.properties` and fill it with your local release keystore values before building a release app bundle. Do not commit real signing secrets.
