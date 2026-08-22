// Placeholder Firebase configuration for StyleLink.
//
// IMPORTANT: Run `flutterfire configure` to replace these placeholders
// with your real Firebase project values. The app works without FCM on web,
// but push notifications require real Firebase config.
//
// To set up:
//   1. Create a Firebase project at https://console.firebase.google.com
//   2. Install FlutterFire CLI: dart pub global activate flutterfire_cli
//   3. Login: firebase login
//   4. Configure: flutterfire configure

import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, TargetPlatform;

/// Default [FirebaseOptions] for use with your Firebase apps.
///
/// To regenerate this file run `flutterfire configure`.
class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.iOS:
        return ios;
      case TargetPlatform.macOS:
        return macos;
      case TargetPlatform.windows:
        return windows;
      case TargetPlatform.linux:
        return linux;
      default:
        return web;
    }
  }

  // ─── PLACEHOLDER VALUES ───────────────────────────────────────────────
  // Replace these with your real Firebase project values after running
  // `flutterfire configure`. The app will still work — FCM is guarded
  // by try-catch in main.dart and notification_service.dart.

  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'AIzaSyBB8JZHSH4jqYIYWImFWNMmXVMovia24I0',
    appId: '1:246740680949:web:3fb6126d1004a110db45bc',
    messagingSenderId: '246740680949',
    projectId: 'stylelink-505716',
    authDomain: 'stylelink-505716.firebaseapp.com',
    storageBucket: 'stylelink-505716.firebasestorage.app',
  );

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyBB8JZHSH4jqYIYWImFWNMmXVMovia24I0',
    appId: '1:246740680949:android:2467406809490000000000',
    messagingSenderId: '246740680949',
    projectId: 'stylelink-505716',
    storageBucket: 'stylelink-505716.firebasestorage.app',
  );

  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'AIzaSyBB8JZHSH4jqYIYWImFWNMmXVMovia24I0',
    appId: '1:246740680949:ios:2467406809490000000000',
    messagingSenderId: '246740680949',
    projectId: 'stylelink-505716',
    storageBucket: 'stylelink-505716.firebasestorage.app',
    iosBundleId: 'com.stylelink.app',
  );

  // Note: macos appId is a placeholder — run flutterfire configure to get real values.
  static const FirebaseOptions macos = FirebaseOptions(
    apiKey: 'AIzaSyBB8JZHSH4jqYIYWImFWNMmXVMovia24I0',
    appId: '1:246740680949:macos:2467406809490000000000',
    messagingSenderId: '246740680949',
    projectId: 'stylelink-505716',
    storageBucket: 'stylelink-505716.firebasestorage.app',
    iosBundleId: 'com.stylelink.app',
  );

  static const FirebaseOptions windows = FirebaseOptions(
    apiKey: 'AIzaSyBB8JZHSH4jqYIYWImFWNMmXVMovia24I0',
    appId: '1:246740680949:web:2467406809490000000000',
    messagingSenderId: '246740680949',
    projectId: 'stylelink-505716',
    authDomain: 'stylelink-505716.firebaseapp.com',
    storageBucket: 'stylelink-505716.firebasestorage.app',
  );

  static const FirebaseOptions linux = FirebaseOptions(
    apiKey: 'AIzaSyBB8JZHSH4jqYIYWImFWNMmXVMovia24I0',
    appId: '1:246740680949:web:2467406809490000000000',
    messagingSenderId: '246740680949',
    projectId: 'stylelink-505716',
    authDomain: 'stylelink-505716.firebaseapp.com',
    storageBucket: 'stylelink-505716.firebasestorage.app',
  );
}
