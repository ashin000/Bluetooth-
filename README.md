# MeshMessage Hybrid

Flutter prototype for an offline-first Bluetooth + LoRa messenger.

## Product decisions

- Account registration and login use Firebase Authentication and require internet.
- **Continue as Guest** is available without registration. Guest mode does not create a Firebase UID.
- Firebase is optional for entering the app; a Firebase initialization or network failure must not block guest access.
- The intended message transport is direct Bluetooth or a compatible LoRa accessory. Internet is not intended to carry offline messages.
- Cloud account/profile services are separate from offline message transport.

## Current implementation status

- Firebase email/password registration and login for registered users.
- Username claims and account profiles in Cloud Firestore.
- Guest entry and guest-session preference stored locally with SharedPreferences.
- Bluetooth tab with scan, server, connect and disconnect controls.
- LoRa accessory BLE screen retained.
- Registered-user chat inbox currently uses Cloud Firestore and is **online-only**. It is not yet the offline transport.
- Guest mode currently provides the offline entry shell and Bluetooth device controls. A local SQLite conversation store, peer discovery/identity exchange, and message routing into Bluetooth/LoRa are still required before end-to-end offline chat is complete.
- Bluetooth prototype payload limit is 20 UTF-8 bytes.
- LoRa radio transmission remains disabled in the supplied prototype firmware until the compliant Indian WPC radio profile is confirmed.

## Firebase setup

Firebase is optional for app entry and is used only for registered accounts/profile features. Offline guest entry does not require Firebase configuration.

1. Create a Firebase project.
2. Enable **Authentication → Sign-in method → Email/Password** and create a Cloud Firestore database if you want registered accounts.
3. Copy `firebase.local.example.json` to `firebase.local.json` on your development machine.
4. Replace the placeholders with your own Firebase client configuration values.
5. Build with `--dart-define-from-file=firebase.local.json`. The local file is ignored by Git. Do not upload it or paste its values into public chats/issues.
6. Publish the included `firestore.rules` from Firebase Console → Firestore Database → Rules.

The application initializes Firebase using explicit `FirebaseOptions`; it does not require a committed `google-services.json` or generated `firebase_options.dart`. Client configuration is not a substitute for Firestore rules or App Check. Never commit `.env` files, local Firebase JSON, signing keys, Admin SDK service-account keys, private credentials, or production secrets.

## Run and validate

```bash
flutter pub get
flutter analyze
flutter test
flutter build apk --release --dart-define-from-file=firebase.local.json
```

These commands must be run in a complete Flutter/Android project on a computer with Flutter and Android SDK installed. The current repository branch does not contain the standard Android Gradle wrapper/settings/app files, so an APK cannot yet be built from this branch. GitHub Actions will run Dart validation and only attempt an APK build once the Android Gradle project is present. This branch has not been compiled or device-tested here.

## Security and radio limitations

- Current Bluetooth messages are plaintext, one-hop and limited to 20 UTF-8 bytes.
- Do not use this prototype for private or sensitive communication.
- Production requires end-to-end encryption, key management, message acknowledgements, replay protection, identity verification, and abuse controls.
- LoRa transmission must remain disabled until legal frequency, bandwidth, spreading factor, transmit power, duty-cycle and hardware settings are verified for the intended region.
