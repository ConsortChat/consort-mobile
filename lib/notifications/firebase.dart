import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

import '../firebase_options.dart';
import '../model/binding.dart';
import 'receive.dart';

/// The [RemotePushNotifications] implementation, using FCM through Firebase.
///
/// This is used in the Google Play and iOS builds of the app.
/// The F-Droid build must not import this library, even indirectly,
/// because F-Droid doesn't accept Firebase; see docs/android-distribution.md.
class FirebaseRemotePushNotifications implements RemotePushNotifications {
  @override
  Future<void> initialize() async {
    final options = switch (defaultTargetPlatform) {
      TargetPlatform.android => kFirebaseOptionsAndroid,
      TargetPlatform.iOS     => kFirebaseOptionsIos,
      _ => throw UnsupportedError('Firebase is not configured for $defaultTargetPlatform'),
    };
    await Firebase.initializeApp(options: options);
  }

  @override
  Future<PushAuthorizationStatus> requestPermission({
    bool alert = true,
    bool announcement = false,
    bool badge = true,
    bool carPlay = false,
    bool criticalAlert = false,
    bool provisional = false,
    bool sound = true,
    bool providesAppNotificationSettings = false,
  }) async {
    final settings = await FirebaseMessaging.instance.requestPermission(
      alert: alert,
      announcement: announcement,
      badge: badge,
      carPlay: carPlay,
      criticalAlert: criticalAlert,
      provisional: provisional,
      sound: sound,
      providesAppNotificationSettings: providesAppNotificationSettings);
    return switch (settings.authorizationStatus) {
      AuthorizationStatus.authorized    => PushAuthorizationStatus.authorized,
      AuthorizationStatus.denied        => PushAuthorizationStatus.denied,
      AuthorizationStatus.notDetermined => PushAuthorizationStatus.notDetermined,
      AuthorizationStatus.provisional   => PushAuthorizationStatus.provisional,
    };
  }

  @override
  Future<String?> getToken() => FirebaseMessaging.instance.getToken();

  @override
  Stream<String> get onTokenRefresh => FirebaseMessaging.instance.onTokenRefresh;

  @override
  Future<String?> getAPNSToken() => FirebaseMessaging.instance.getAPNSToken();

  @override
  Stream<RemotePushMessage> get foregroundMessages =>
    FirebaseMessaging.onMessage.map(_convertMessage);

  @override
  void setBackgroundMessageHandler(RemotePushMessageHandler handler) {
    // Firebase runs the background handler in a new isolate, so it must be
    // a top-level or static function, and can't close over [handler].
    assert(handler == NotificationService.onBackgroundMessage);
    FirebaseMessaging.onBackgroundMessage(_onBackgroundMessage);
  }
}

RemotePushMessage _convertMessage(RemoteMessage message) {
  return RemotePushMessage(data: message.data);
}

// This pragma `vm:entry-point` is needed in release mode, when this function
// is needed at all (i.e. on Android):
//   https://firebase.google.com/docs/cloud-messaging/flutter/receive#background_messages
//   https://github.com/firebase/flutterfire/issues/9446#issuecomment-1240554285
//   https://github.com/zulip/zulip-flutter/issues/528#issuecomment-1960646800
@pragma('vm:entry-point')
Future<void> _onBackgroundMessage(RemoteMessage message) {
  return NotificationService.onBackgroundMessage(_convertMessage(message));
}
