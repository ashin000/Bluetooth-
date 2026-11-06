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

Firebase is used for account registration/login and profile lookup, not as the required message transport.

1. Create a Firebase project and register the Android app with the exact application ID used by the Android Gradle configuration.
2. Enable **Authentication → Sign-in method → Email/Password**.
3. Create a Cloud Firestore database.
4. Configure FlutterFire for the project and ensure `lib/firebase_options.dart` and the Android Google Services configuration match your project.
5. Publish `firestore.rules` from Firebase Console → Firestore Database → Rules.

Never commit `.env` files, Firebase config files, signing keys, Admin SDK service-account keys, private credentials, or production secrets. `.gitignore` excludes local Firebase configuration, but always check `git status` before committing.

## Run and validate

```bash
flutter pub get
flutter analyze
flutter test
flutter build apk --release
```

These commands must be run in a complete Flutter/Android project on a computer with Flutter and Android SDK installed. This repository change has not been compiled or device-tested here.

## Security and radio limitations

- Current Bluetooth messages are plaintext, one-hop and limited to 20 UTF-8 bytes.
- Do not use this prototype for private or sensitive communication.
- Production requires end-to-end encryption, key management, message acknowledgements, replay protection, identity verification, and abuse controls.
- LoRa transmission must remain disabled until legal frequency, bandwidth, spreading factor, transmit power, duty-cycle and hardware settings are verified for the intended region.
