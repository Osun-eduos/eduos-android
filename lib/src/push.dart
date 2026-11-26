// Push notifications through Firebase Cloud Messaging. They are switched on only when the app is built with the
// Firebase project's settings, for example:
//   flutter build apk --dart-define=FIREBASE_API_KEY=... --dart-define=FIREBASE_PROJECT_ID=... \
//     --dart-define=FIREBASE_SENDER_ID=... --dart-define=FIREBASE_ANDROID_APP_ID=... --dart-define=FIREBASE_IOS_APP_ID=...
// Without them the app works the same, and parents see notifications in the inbox and by SMS.
import 'dart:async';
import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

const _apiKey = String.fromEnvironment('FIREBASE_API_KEY');
const _projectId = String.fromEnvironment('FIREBASE_PROJECT_ID');
const _senderId = String.fromEnvironment('FIREBASE_SENDER_ID');
const _androidAppId = String.fromEnvironment('FIREBASE_ANDROID_APP_ID');
const _iosAppId = String.fromEnvironment('FIREBASE_IOS_APP_ID');

/// Gives the phone's push address and tells the app when a notification arrives while it is open.
abstract class PushRegistrar {
  /// The phone's push token, or null when push is not available.
  Future<String?> token();
  Stream<String> get tokenChanges;
  /// A notification arrived or was tapped: refresh the inbox.
  Stream<void> get arrivals;
  String get platform => Platform.isIOS ? 'ios' : 'android';
}

class NoPush extends PushRegistrar {
  @override
  Future<String?> token() async => null;
  @override
  Stream<String> get tokenChanges => const Stream.empty();
  @override
  Stream<void> get arrivals => const Stream.empty();
}

class FirebasePush extends PushRegistrar {
  static bool get configured => _apiKey.isNotEmpty && _projectId.isNotEmpty && _senderId.isNotEmpty && (Platform.isIOS ? _iosAppId : _androidAppId).isNotEmpty;
  bool _ready = false;
  final _arrivals = StreamController<void>.broadcast();

  Future<bool> _init() async {
    if (_ready) return true;
    if (!configured) return false;
    try {
      await Firebase.initializeApp(
          options: FirebaseOptions(apiKey: _apiKey, appId: Platform.isIOS ? _iosAppId : _androidAppId, messagingSenderId: _senderId, projectId: _projectId));
      final m = FirebaseMessaging.instance;
      final perm = await m.requestPermission();
      if (perm.authorizationStatus == AuthorizationStatus.denied) return false;
      FirebaseMessaging.onMessage.listen((_) => _arrivals.add(null));
      FirebaseMessaging.onMessageOpenedApp.listen((_) => _arrivals.add(null));
      _ready = true;
    } catch (e) {
      debugPrint('Push is off: $e');
    }
    return _ready;
  }

  // The API sends with FCM HTTP v1 to a registration token. Firebase now also offers installation-ID registration
  // (register() and onRegistered); move to it once the API sends that way too.
  @override
  // ignore: deprecated_member_use
  Future<String?> token() async => await _init() ? FirebaseMessaging.instance.getToken() : null;
  @override
  // ignore: deprecated_member_use
  Stream<String> get tokenChanges => _ready ? FirebaseMessaging.instance.onTokenRefresh : const Stream.empty();
  @override
  Stream<void> get arrivals => _arrivals.stream;
}
