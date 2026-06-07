// File generated manually from google-services.json values.
// Project: delimap-app-2026
// This file provides explicit FirebaseOptions so Firebase.initializeApp()
// correctly initialises the Firestore client on every platform.

import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      throw UnsupportedError(
        'DefaultFirebaseOptions have not been configured for web - '
        'you can reconfigure this by running the FlutterFire CLI again.',
      );
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.iOS:
        throw UnsupportedError(
          'DefaultFirebaseOptions have not been configured for iOS.',
        );
      default:
        throw UnsupportedError(
          'DefaultFirebaseOptions are not supported for this platform.',
        );
    }
  }

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyCOWgT1wEy1CbsPb3XR3Gcbdlg-V8fyJak',
    appId: '1:889058764875:android:784413148af1c077bc85ce',
    messagingSenderId: '889058764875',
    projectId: 'delimap-app-2026',
    storageBucket: 'delimap-app-2026.firebasestorage.app',
  );
}
