# MeshMessage Hybrid v0.3

Flutter prototype for an offline-first Bluetooth + LoRa messenger.

## UI updates
- WhatsApp-inspired chat screen with bubbles, composer, transport status and new-chat action.
- Dedicated Settings tab for account, Bluetooth controls and LoRa accessory configuration.
- Existing advanced LoRa accessory screen retained.

## Account registration and login
Firebase Authentication (email/password) handles credentials. Cloud Firestore stores the MeshMessage UID and username profile. Credentials are not stored in Firestore.

### Configure Firebase
1. Create a Firebase project and register the Android app using the package ID in the Android Gradle configuration.
2. Enable Authentication → Email/Password and create a Cloud Firestore database.
3. Install FlutterFire CLI and run:
   ```bash
   dart pub global activate flutterfire_cli
   flutterfire configure
   ```
4. Import generated firebase_options.dart in main.dart and initialize with DefaultFirebaseOptions.currentPlatform.
5. Apply the included firestore.rules.

## Build
```bash
flutter pub get
flutter analyze
flutter test
flutter build apk --release
```

## Prototype limits
- A UID label is not proof of recipient ownership. Production should enforce unique username/UID claims with a transaction or trusted backend.
- Bluetooth messages are plaintext, one-hop and limited to 20 UTF-8 bytes.
- LoRa accessory firmware remains transmission-disabled pending confirmation of the exact Indian WPC-compliant radio profile.
- Messages remain in local screen memory only. Durable conversations, UID lookup, end-to-end encryption, message relays and delivery acknowledgements are not included in this milestone.
