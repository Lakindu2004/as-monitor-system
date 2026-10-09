// File generated to support Firebase initialization using your google-services.json credentials
import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      return web;
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.iOS:
        throw UnsupportedError(
          'DefaultFirebaseOptions have not been configured for iOS - '
          'you can configure this by running the FlutterFire CLI.',
        );
      case TargetPlatform.macOS:
        throw UnsupportedError(
          'DefaultFirebaseOptions have not been configured for macos - '
          'you can configure this by running the FlutterFire CLI.',
        );
      case TargetPlatform.windows:
        throw UnsupportedError(
          'DefaultFirebaseOptions have not been configured for windows - '
          'you can configure this by running the FlutterFire CLI.',
        );
      case TargetPlatform.linux:
        throw UnsupportedError(
          'DefaultFirebaseOptions have not been configured for linux - '
          'you can configure this by running the FlutterFire CLI.',
        );
      default:
        throw UnsupportedError(
          'DefaultFirebaseOptions are not supported for this platform.',
        );
    }
  }

  static const FirebaseOptions web = FirebaseOptions(
    apiKey: const String.fromEnvironment('FIREBASE_API_KEY', defaultValue: ''),
    appId: '1:793511631765:web:patientmonitorweb',
    messagingSenderId: '793511631765',
    projectId: 'patient-monitor-1bf49',
    databaseURL: 'https://patient-monitor-1bf49-default-rtdb.firebaseio.com',
    storageBucket: 'patient-monitor-1bf49.firebasestorage.app',
  );

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: const String.fromEnvironment('FIREBASE_API_KEY', defaultValue: ''),
    appId: '1:793511631765:android:4abb8add420ea2609bf49c',
    messagingSenderId: '793511631765',
    projectId: 'patient-monitor-1bf49',
    databaseURL: 'https://patient-monitor-1bf49-default-rtdb.firebaseio.com',
    storageBucket: 'patient-monitor-1bf49.firebasestorage.app',
  );
}
