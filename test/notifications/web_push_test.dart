import 'dart:convert';
import 'dart:typed_data';

import 'package:checks/checks.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:unifiedpush_platform_interface/data/public_key_set.dart';
import 'package:unifiedpush_platform_interface/data/push_endpoint.dart';
import 'package:unifiedpush_platform_interface/data/push_message.dart';
import 'package:zulip/host/android_notifications.dart';
import 'package:zulip/model/narrow.dart';
import 'package:zulip/model/store.dart';
import 'package:zulip/notifications/display.dart';
import 'package:zulip/notifications/open.dart';
import 'package:zulip/notifications/web_push.dart';

import '../api/fake_api.dart';
import '../example_data.dart' as eg;
import '../model/binding.dart';
import '../stdlib_checks.dart';

void main() {
  TestZulipBinding.ensureInitialized();

  const vapidKey =
    'BNcRdreALRFXTkOOUHK1EtK2wtaz5Ry4YfYCA_0QTpQtUbVlUls0VJXg7A8u-Ts1XbjhazAkj7I99e8QcYP7DkM';
  const endpointUrl = 'https://ntfy.example.test/UPqcpQxYzS6bH9';
  final endpointKeys = PublicKeySet(
    'BJ2xmvJ0h6nJVqLQ0sKz8jUXhVBqNC8oXxwWXhqPBhZ',
    'k8JV6sjdbhAi3TrqFVwzZg');

  void prepare() {
    addTearDown(testBinding.reset);
    addTearDown(WebPushService.debugReset);
    testBinding.globalStore.useCachedApiConnections = true;
  }

  Future<void> addAccount(Account account) async {
    await testBinding.globalStore.add(account, eg.initialSnapshot());
  }

  FakeApiConnection prepareConfig(Account account, {required bool enabled}) {
    final connection = testBinding.globalStore
      .apiConnectionFromAccount(account) as FakeApiConnection;
    connection.prepare(json: {
      'web_push_enabled': enabled,
      'vapid_public_key': enabled ? vapidKey : '',
    });
    return connection;
  }

  Future<void> startForAccount(Account account) async {
    await addAccount(account);
    prepareConfig(account, enabled: true);
    testBinding.unifiedPush.hasDefaultDistributor = true;
    await WebPushService.instance.start();
  }

  PushMessage message(Map<String, dynamic> json, {bool decrypted = true}) {
    return PushMessage(Uint8List.fromList(utf8.encode(jsonEncode(json))), decrypted);
  }

  group('registration', () {
    test('no distributor', () async {
      prepare();
      await addAccount(eg.selfAccount);

      await WebPushService.instance.start();

      check(WebPushService.instance.distributorMissing.value).isTrue();
      check(testBinding.unifiedPush.takeRegisterCalls()).isEmpty();
    });

    test('registers accounts whose server supports Web Push', () async {
      prepare();
      await addAccount(eg.selfAccount);
      await addAccount(eg.otherAccount);
      final enabledConnection = prepareConfig(eg.selfAccount, enabled: true);
      final disabledConnection = prepareConfig(eg.otherAccount, enabled: false);
      testBinding.unifiedPush.hasDefaultDistributor = true;

      await WebPushService.instance.start();

      check(WebPushService.instance.distributorMissing.value).isFalse();
      check(testBinding.unifiedPush.takeRegisterCalls()).deepEquals([
        (instance: eg.selfAccount.id.toString(), vapid: vapidKey),
      ]);
      check(enabledConnection.takeRequests()).single.isA<http.Request>()
        ..method.equals('GET')
        ..url.path.equals('/api/v1/users/me/web_push_subscription');
      check(disabledConnection.takeRequests()).single.isA<http.Request>()
        ..method.equals('GET')
        ..url.path.equals('/api/v1/users/me/web_push_subscription');
      check(enabledConnection.isOpen).isFalse();
      check(disabledConnection.isOpen).isFalse();
    });

    test('registers an account added after startup', () async {
      prepare();
      testBinding.unifiedPush.hasDefaultDistributor = true;
      await WebPushService.instance.start();
      final connection = prepareConfig(eg.selfAccount, enabled: true);

      await addAccount(eg.selfAccount);
      await Future<void>.delayed(const Duration(milliseconds: 10));

      check(testBinding.unifiedPush.takeRegisterCalls()).deepEquals([
        (instance: eg.selfAccount.id.toString(), vapid: vapidKey),
      ]);
      check(connection.takeRequests()).length.equals(1);
    });

    test('a failed registration does not stop later accounts', () async {
      prepare();
      await addAccount(eg.selfAccount);
      await addAccount(eg.otherAccount);
      prepareConfig(eg.selfAccount, enabled: true);
      prepareConfig(eg.otherAccount, enabled: true);
      testBinding.unifiedPush
        ..hasDefaultDistributor = true
        ..registerException = Exception('registration failed');

      await WebPushService.instance.start();

      check(testBinding.unifiedPush.takeRegisterCalls()).deepEquals([
        (instance: eg.selfAccount.id.toString(), vapid: vapidKey),
        (instance: eg.otherAccount.id.toString(), vapid: vapidKey),
      ]);
    });
  });

  group('endpoint', () {
    test('stores subscription on the account server', () async {
      prepare();
      await startForAccount(eg.selfAccount);
      testBinding.unifiedPush.takeRegisterCalls();
      final connection = testBinding.globalStore
        .apiConnectionFromAccount(eg.selfAccount) as FakeApiConnection
        ..prepare(json: {});

      await testBinding.unifiedPush.sendNewEndpoint(
        PushEndpoint(endpointUrl, endpointKeys), eg.selfAccount.id.toString());

      check(connection.takeRequests()).single.isA<http.Request>()
        ..method.equals('POST')
        ..url.path.equals('/api/v1/users/me/web_push_subscription')
        ..bodyFields.deepEquals({
          'endpoint': endpointUrl,
          'p256dh': endpointKeys.pubKey,
          'auth': endpointKeys.auth,
        });
      check(connection.isOpen).isFalse();
    });

    test('without encryption keys is ignored', () async {
      prepare();
      await startForAccount(eg.selfAccount);

      await testBinding.unifiedPush.sendNewEndpoint(
        PushEndpoint(endpointUrl, null), eg.selfAccount.id.toString());

      check(testBinding.unifiedPush.takeUnregisterCalls()).isEmpty();
    });

    test('for a removed account is unregistered', () async {
      prepare();
      await WebPushService.instance.start();

      await testBinding.unifiedPush.sendNewEndpoint(
        PushEndpoint(endpointUrl, endpointKeys), '9999');

      check(testBinding.unifiedPush.takeUnregisterCalls()).deepEquals(['9999']);
    });
  });

  group('message', () {
    test('add is displayed and remove clears it', () async {
      prepare();
      await addAccount(eg.selfAccount);
      await WebPushService.instance.startInBackground();
      testBinding.androidNotificationHost.takeNotifyCalls();

      await testBinding.unifiedPush.sendMessage(message({
        'type': 'add',
        'message_id': 123,
        'title': 'Alice',
        'body': 'Hello there',
      }), eg.selfAccount.id.toString());

      final calls = testBinding.androidNotificationHost.takeNotifyCalls();
      check(calls).length.equals(2);
      final notification = calls[0];
      final groupKey = '${eg.selfAccount.realmUrl}|${eg.selfAccount.userId}';
      check(notification.id).equals(NotificationDisplayManager.kNotificationId);
      check(notification.tag).equals('$groupKey|web-push:123');
      check(notification.contentTitle).equals('Alice');
      check(notification.contentText).equals('Hello there');
      check(notification.groupKey).equals(groupKey);
      check(notification.extras).deepEquals({
        NotificationDisplayManager.kExtraLastMessageId: '123',
      });
      final contentIntent = notification.contentIntent!;
      check(contentIntent.flags).equals(PendingIntentFlag.immutable);
      check(contentIntent.intent.dataUrl).isNotNull();
      final openPayload = NotificationOpenPayload.parseNotificationUrl(
        Uri.parse(contentIntent.intent.dataUrl));
      check(openPayload.realmUrl).equals(eg.selfAccount.realmUrl);
      check(openPayload.userId).equals(eg.selfAccount.userId);
      check(openPayload.narrow).isA<CombinedFeedNarrow>();
      check(openPayload.messageId).equals(123);
      check(calls[1].tag).equals(groupKey);
      check(calls[1].isGroupSummary).equals(true);
      check(testBinding.androidNotificationHost.activeNotifications)
        .length.equals(2);

      await testBinding.unifiedPush.sendMessage(message({
        'type': 'remove',
        'message_ids': [123],
      }), eg.selfAccount.id.toString());

      check(testBinding.androidNotificationHost.activeNotifications).isEmpty();
    });

    test('undecrypted, malformed, and unknown-account messages are ignored', () async {
      prepare();
      await addAccount(eg.selfAccount);
      await WebPushService.instance.startInBackground();
      testBinding.androidNotificationHost.takeNotifyCalls();
      final validJson = {
        'type': 'add',
        'message_id': 123,
        'title': 'Alice',
        'body': 'Hello there',
      };

      await testBinding.unifiedPush.sendMessage(
        message(validJson, decrypted: false), eg.selfAccount.id.toString());
      await testBinding.unifiedPush.sendMessage(
        PushMessage(Uint8List.fromList([0xff]), true), eg.selfAccount.id.toString());
      await testBinding.unifiedPush.sendMessage(message(validJson), '9999');

      check(testBinding.androidNotificationHost.takeNotifyCalls()).isEmpty();
    });
  });

  test('unregister removes a known subscription', () async {
    prepare();
    await startForAccount(eg.selfAccount);
    final addConnection = testBinding.globalStore
      .apiConnectionFromAccount(eg.selfAccount) as FakeApiConnection
      ..prepare(json: {});
    await testBinding.unifiedPush.sendNewEndpoint(
      PushEndpoint(endpointUrl, endpointKeys), eg.selfAccount.id.toString());
    check(addConnection.takeRequests()).length.equals(1);

    final removeConnection = testBinding.globalStore
      .apiConnectionFromAccount(eg.selfAccount) as FakeApiConnection
      ..prepare(json: {});
    await WebPushService.instance.unregister(eg.selfAccount, removeConnection);

    check(testBinding.unifiedPush.takeUnregisterCalls())
      .deepEquals([eg.selfAccount.id.toString()]);
    check(removeConnection.takeRequests()).single.isA<http.Request>()
      ..method.equals('DELETE')
      ..url.path.equals('/api/v1/users/me/web_push_subscription')
      ..bodyFields.deepEquals({'endpoint': endpointUrl});
  });
}
