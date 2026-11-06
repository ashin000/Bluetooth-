# MeshMessage

A lightweight Flutter UI prototype for nearby Bluetooth and LoRa accessory messaging.

## Build prerequisites

This repository must be a complete Flutter project containing the Android Gradle wrapper and native Android app configuration. The current branch does not yet contain those Android files, so a release APK cannot be built until the native project structure is restored.

## Dependencies

- Flutter
- flutter_blue_plus
- shared_preferences

Firebase has been removed from the app and is not required.

## Local build

```bash
flutter pub get
flutter analyze
flutter test
flutter build apk --release
```

## Current prototype limits

- The UI includes Chats, Nearby Devices and Settings.
- Bluetooth phone-to-phone bridge methods depend on native Android channel implementation.
- Bluetooth test messages are limited to 20 UTF-8 bytes.
- LoRa accessory discovery and its BLE bridge UI are included.
- Radio transmission must remain disabled until the hardware and compliant regional radio profile are verified.
- Messages are currently in-memory only. Persistent local history, delivery acknowledgements, encryption and mesh routing are not implemented.

Do not use this prototype for private or sensitive communication.
