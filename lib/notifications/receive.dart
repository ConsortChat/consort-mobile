import 'dart:async';
import 'dart:convert';

import 'package:collection/collection.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';

import '../api/core.dart';
import '../api/notifications.dart';
import '../api/route/notifications.dart';
import '../log.dart';
import '../model/binding.dart';
import '../model/push_key.dart';
import '../model/store.dart';
import 'display.dart';
import 'open.dart';
import 'web_push.dart';

@pragma('vm:entry-point')
class NotificationService {
  static NotificationService get instance => (_instance ??= NotificationService._());
  static NotificationService? _instance;

  NotificationService._();

  /// Reset the state of the [NotificationService], for testing.
  ///
  /// TODO refactor this better, perhaps unify with ZulipBinding
  @visibleForTesting
  static void debugReset() {
    WebPushService.debugReset();
    instance.token.dispose();
    _instance = null;
    assert(debugBackgroundIsolateIsLive = true);
    NotificationOpenService.debugReset();
  }

  /// Whether a background isolate should initialize [LiveZulipBinding].
  ///
  /// Ordinarily a [RemotePushNotifications.setBackgroundMessageHandler] callback
  /// will be invoked in a background isolate where it must set up its
  /// [ZulipBinding], just as the `main` function does for most of the app.
  /// Consequently, by default we have that callback initialize
  /// [LiveZulipBinding], just like `main` does.
  ///
  /// In a test that behavior is undesirable.  Tests that will cause
  /// [RemotePushNotifications.setBackgroundMessageHandler] callbacks
  /// to get invoked should therefore set this to false.
  static bool debugBackgroundIsolateIsLive = true;

  /// The FCM registration token for this install of the app.
  ///
  /// This is unique to the (app, device) pair, but not permanent.
  /// Most often it's the same from one run of the app to the next,
  /// but it can change either during a run or between them.
  ///
  /// See also:
  ///  * Upstream docs on FCM registration tokens in general:
  ///    https://firebase.google.com/docs/cloud-messaging/manage-tokens
  ValueNotifier<String?> token = ValueNotifier(null);

  static String computeTokenId(String token) {
    final hash = sha256.convert(token.codeUnits).bytes;
    return base64Encode(hash.slice(0, 8));
  }

  Future<void> start() async {
    await NotificationOpenService.instance.start();

    final remotePush = ZulipBinding.instance.remotePushNotifications;
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        await NotificationDisplayManager.init();
        // Consort's server sends notifications by Web Push; see WebPushService.
        unawaited(WebPushService.instance.start());

        if (remotePush == null) {
          // This build has no FCM (it's the F-Droid build),
          // so Firebase won't request the notification permission for us.
          await ZulipBinding.instance.androidNotificationHost
            .requestNotificationPermission(); // TODO(#324): defer if not logged into any accounts
          return;
        }
        await remotePush.initialize();
        remotePush.foregroundMessages.listen(_onForegroundMessage);
        remotePush.setBackgroundMessageHandler(onBackgroundMessage);

        await _requestPermission(remotePush); // TODO(#324): defer if not logged into any accounts
        // On Android, the notification permission is only about showing
        // notifications in the UI, not about getting notification data in the
        // background.  Even if the app lacks permission to show notifications
        // in the UI, it's useful to get the token and enable the user's Zulip
        // servers to send notification data to the client, because it means if
        // the user later enables notifications, they'll promptly start working.

        // Get the FCM registration token, now and upon changes.  See FCM API docs:
        //   https://firebase.google.com/docs/cloud-messaging/android/client#sample-register
        remotePush.onTokenRefresh
          .listen(_onTokenRefresh);
        await _getFcmToken(remotePush);

      case TargetPlatform.iOS: // TODO(#324): defer requesting notif permission
        if (remotePush == null) return;
        await remotePush.initialize();

        if (!await _requestPermission(remotePush)) {
          // TODO(#324): request only "provisional" permission at this stage:
          //   https://github.com/zulip/zulip-flutter/issues/324#issuecomment-1771400325
          //   then proceed to get and use the token just like on Android
          return;
        }

        await _getApnsToken(remotePush);
        // TODO does iOS need token refresh too?

      case TargetPlatform.linux:
      case TargetPlatform.macOS:
      case TargetPlatform.windows:
      case TargetPlatform.fuchsia:
        // Do nothing; we don't offer notifications on these platforms.
        break;
    }
  }

  Future<bool> _requestPermission(RemotePushNotifications remotePush) async {
    // Docs on this API: https://firebase.flutter.dev/docs/messaging/permissions/
    final status = await remotePush.requestPermission();
    assert(debugLog('notif authorization: $status'));
    switch (status) {
      case PushAuthorizationStatus.denied:
        return false;
      case PushAuthorizationStatus.authorized:
      case PushAuthorizationStatus.provisional:
      case PushAuthorizationStatus.notDetermined:
        return true;
    }
  }

  Future<void> _getFcmToken(RemotePushNotifications remotePush) async {
    final value = await remotePush.getToken();
    // TODO(#323) warn user if getToken returns null, or doesn't timely return
    assert(debugLog("notif FCM token: $value"));
    // The call to `getToken` won't cause `onTokenRefresh` to fire if we
    // already have a token from a previous run of the app.
    // So we need to use the `getToken` return value.
    token.value = value;
  }

  Future<void> _getApnsToken(RemotePushNotifications remotePush) async {
    final value = await remotePush.getAPNSToken();
    // TODO(#323) warn user if getAPNSToken returns null, or doesn't timely return
    assert(debugLog("notif APNs token: $value"));
    token.value = value;
  }

  void _onTokenRefresh(String value) {
    assert(debugLog("new notif token: $value"));
    // On first launch after install, our [FirebaseMessaging.getToken] call
    // causes this to fire, followed by completing its own future so that
    // `_getToken` sees the value as well.  So in that case this is redundant.
    //
    // Subsequently, though, this can also potentially fire on its own, if for
    // some reason the FCM system decides to replace the token.  So both paths
    // need to save the value.
    token.value = value;
  }

  static Future<void> unregisterToken(ApiConnection connection, {required String token}) async {
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        await removeFcmToken(connection, token: token);

      case TargetPlatform.iOS:
        await removeApnsToken(connection, token: token);

      case TargetPlatform.linux:
      case TargetPlatform.macOS:
      case TargetPlatform.windows:
      case TargetPlatform.fuchsia:
        assert(false);
    }
  }

  static void _onForegroundMessage(RemotePushMessage message) {
    assert(debugLog("notif message: ${message.data}"));
    _onRemoteMessage(message);
  }

  /// The handler for [RemotePushNotifications.setBackgroundMessageHandler].
  static Future<void> onBackgroundMessage(RemotePushMessage message) async {
    // This callback will run in a separate isolate from the rest of the app.
    // See docs:
    //   https://firebase.flutter.dev/docs/messaging/usage/#background-messages
    _initBackgroundIsolate();

    assert(debugLog("notif message in background: ${message.data}"));
    _onRemoteMessage(message);
  }

  static void _initBackgroundIsolate() {
    bool isolateIsLive = true;
    assert(() {
      isolateIsLive = debugBackgroundIsolateIsLive;
      return true;
    }());
    if (!isolateIsLive) {
      return;
    }

    // Compare these setup steps to the ones in `runMain` in lib/main_common.dart .
    assert(() {
      debugLogEnabled = true;
      return true;
    }());
    LiveZulipBinding.ensureInitialized();
    NotificationDisplayManager.init(); // TODO call this just once per isolate
  }

  static void _onRemoteMessage(RemotePushMessage message) async {
    assert(defaultTargetPlatform == TargetPlatform.android);
    final origData = message.data;

    EncryptedFcmMessage? parsed;
    try {
      parsed = EncryptedFcmMessage.fromJson(origData);
    } catch (_) {
      // Presumably a non-E2EE notification.  // TODO(server-12)
      await _onPlaintextRemoteMessage(origData);
      return;
    }

    final result = await decryptNotification(parsed.pushKeyId, parsed.encryptedData);
    if (result == null) return;

    final (data, account) = result;
    NotificationDisplayManager.onNotifPayload(data, account);
  }

  static Future<void> _onPlaintextRemoteMessage(Map<String, dynamic> rawData) async {
    final data = LegacyFcmMessage.fromJson(rawData);
    switch (data) {
      case NotifPayloadWithIdentity(): break;
      case UnexpectedNotifPayload(): return; // TODO(log)
    }

    final globalStore = await ZulipBinding.instance.getGlobalStore();
    final account = globalStore.accounts.firstWhereOrNull((account) =>
      account.realmUrl.origin == data.realmUrl.origin && account.userId == data.userId);

    // Skip showing notifications for a logged-out account. This can occur if
    // the unregisterToken request failed previously. It would be annoying
    // to the user if notifications keep showing up after they've logged out.
    // (Also alarming: it suggests the logout didn't fully work.)
    if (account == null) {
      return;
    }

    assert(defaultTargetPlatform == TargetPlatform.android);
    if (account.zulipFeatureLevel >= 468) {
      // The server is new enough for E2EE notifications, but this is a legacy
      // plaintext notification.  It's normal to potentially get these when
      // either client or server is first upgraded to add E2EE support, because
      // the two subsystems register for push notifications independently.
      //
      // (At FL 483+, registering for E2EE notifications will cause the server
      // to usually stop sending legacy notifications; but even then, if the
      // user has other devices that are still registered only for legacy
      // notifications, this device will potentially continue to get them too.)
      //
      // Just ignore the legacy notification.  // TODO(log)
      return;
    }

    NotificationDisplayManager.onNotifPayload(data, account);
  }

  /// Decrypt an E2EE notification content.
  ///
  /// Returns a future resolving to null if it encounters an error.
  static Future<(NotifPayloadWithIdentity, Account)?> decryptNotification(
    int pushKeyId,
    Uint8List encryptedData,
  ) async {
    final globalStore = await ZulipBinding.instance.getGlobalStore();
    final pushKey = globalStore.pushKeys.getPushKeyById(pushKeyId);
    if (pushKey == null) {
      // Not a key we have; nothing we can do with this notification-message.
      // This can happen if it's addressed to an account that's been logged out.
      // (On logout we try to unregister the device, but that can fail if the
      // device isn't able to reach the server at that time.)
      return null; // TODO(log)
    }
    final account = globalStore.getAccount(pushKey.accountId)!;

    final plaintext = await PushKeyStore.decryptNotification(
      pushKey.pushKey, encryptedData);
    final rawData = jsonUtf8Decoder.convert(plaintext) as Map<String, dynamic>;
    final data = NotifPayload.fromJson(rawData);
    switch (data) {
      case NotifPayloadWithIdentity(): break;
      case UnexpectedNotifPayload(): return null; // TODO(log)
    }

    if (!(account.realmUrl.origin == data.realmUrl.origin
          && account.userId == data.userId)) {
      assert(debugLog("bad notif payload: realm/userId fails to match push key"));
      return null; // TODO(log)
    }

    return (data, account);
  }
}
