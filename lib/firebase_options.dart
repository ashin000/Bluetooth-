// Generated Firebase client configuration for MeshMessage.
// This file contains public client identifiers, not Admin SDK credentials.
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      throw UnsupportedError('MeshMessage Firebase web configuration has not been set up.');
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.iOS:
      case TargetPlatform.macOS:
      case TargetPlatform.windows:
      case TargetPlatform.linux:
      case TargetPlatform.fuchsia:
        throw UnsupportedError('Firebase is currently configured for Android only.');
    }
  }

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyDwMiW7ooKpssRODGIsL7xhM--E7ogNpPM',
    appId: '1:869077551282:android:7a093fa4617562b0dd61ab',
    messagingSenderId: '869077551282',
    projectId: 'meshmessage-11e44',
    storageBucket: 'meshmessage-11e44.firebasestorage.app',
  );
}
