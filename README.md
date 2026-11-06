# MeshMessage Hybrid

Flutter prototype for an offline-first Bluetooth + LoRa messenger.

## Current app features
- Firebase email/password registration and login.
- Unique MeshMessage UID from Firebase Authentication.
- Username claims stored in Firestore to prevent duplicate usernames.
- WhatsApp-inspired chat interface and message bubbles.
- Bluetooth tab for server, scan, connect and disconnect.
- Settings tab showing account UID and Bluetooth / LoRa accessory controls.
- Existing BLE-to-LoRa accessory screen retained.

## Firebase setup (required before the app can run)
1. Create a Firebase project.
2. Register the Android app using the exact Android application ID from `android/app/build.gradle` or `android/app/build.gradle.kts`. The native activity currently declares package `com.example.mesh_message`; verify the Gradle application ID matches it.
3. In Firebase Console, enable **Authentication → Sign-in method → Email/Password**.
4. Create a **Cloud Firestore** database.
5. On a computer with Flutter installed, run:
   ```bash
   dart pub global activate flutterfire_cli
   flutterfire configure
   ```
   Select the Firebase project and Android app. This generates `lib/firebase_options.dart` and configures the native Firebase Gradle plugin.
6. Publish the included Firestore rules from Firebase Console → Firestore Database → Rules (or deploy them with Firebase CLI).

The generated `lib/firebase_options.dart` is intentionally not committed: it must match your Firebase project. Do not upload Admin SDK service-account keys or private credentials.

## Run and validate
```bash
flutter pub get
flutter analyze
flutter test
flutter build apk --release
```

## Current prototype limits
- Chat bubbles currently show the live local Bluetooth session; chat history is not persisted to Firestore.
- UID lookup verifies a profile but does not yet create a persistent one-to-one conversation.
- Bluetooth phone-to-phone messages are plaintext, one-hop and limited to 20 UTF-8 bytes.
- The LoRa screen connects to the accessory over BLE. The supplied firmware keeps radio transmission disabled pending confirmation of the compliant Indian WPC radio profile.
- Do not use this prototype for private or sensitive communication. Production requires end-to-end encryption, abuse controls, secure key management and delivery acknowledgements.
