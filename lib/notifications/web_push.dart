import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:unifiedpush_platform_interface/data/failed_reason.dart';
import 'package:unifiedpush_platform_interface/data/push_endpoint.dart';
import 'package:unifiedpush_platform_interface/data/push_message.dart';

import '../api/core.dart';
import '../api/route/web_push.dart';
import '../api/web_push.dart';
import '../log.dart';
import '../model/binding.dart';
import '../model/store.dart';
import 'display.dart';

/// Receives notifications on Android by Web Push, through UnifiedPush.
///
/// Consort's server sends notifications as Web Push itself,
/// rather than through FCM; see lib/api/route/web_push.dart.
/// On the device, a UnifiedPush distributor app the user has installed,
/// such as ntfy, holds the connection to its push server,
/// hands us an endpoint URL for our server to push to,
/// and decrypts what arrives there before passing it to us.
///
/// Each account is its own UnifiedPush "instance", named by its account ID,
/// because the server's payloads don't say which account they're for.
class WebPushService {
  WebPushService._();

  static WebPushService get instance => (_instance ??= WebPushService._());
  static WebPushService? _instance;

  /// Reset the state of the [WebPushService], for testing.
  static void debugReset() {
    _instance = null;
  }

  /// The argument the UnifiedPush plugin passes to `main`
  /// when it starts a headless engine, to deliver a push
  /// while the app isn't running.
  static const kBackgroundEngineArg = '--unifiedpush-bg';

  /// Whether notifications can't arrive,
  /// because no UnifiedPush distributor could be selected.
  ///
  /// There's no fallback: without a distributor the server has nowhere
  /// to send notifications, and they silently never arrive.
  final ValueNotifier<bool> distributorMissing = ValueNotifier(false);

  /// The accounts we've registered, or tried to, since startup.
  final Set<int> _registeredAccountIds = {};

  /// The endpoint each account's notifications are pushed to,
  /// as learned since startup.
  final Map<int, String> _endpoints = {};

  /// Start receiving notifications, and register accounts for them,
  /// including accounts added later.
  ///
  /// Called by [NotificationService.start],
  /// after it has set up for displaying notifications.
  Future<void> start() async {
    assert(defaultTargetPlatform == TargetPlatform.android);
    await _startReceiving();
    final globalStore = await ZulipBinding.instance.getGlobalStore();
    globalStore.addListener(_onAccountsChanged);
    await _registerNewAccounts();
  }

  /// Everything needed in the headless engine the UnifiedPush plugin starts
  /// to deliver a push while the app isn't running.
  Future<void> startInBackground() async {
    assert(defaultTargetPlatform == TargetPlatform.android);
    await NotificationDisplayManager.init();
    await _startReceiving();
  }

  /// Start handling what the distributor sends: pushes, and new endpoints.
  ///
  /// The plugin holds on to anything that arrives before this is called.
  Future<void> _startReceiving() async {
    await ZulipBinding.instance.unifiedPush.initializeCallback(
      onNewEndpoint: _onNewEndpoint,
      onMessage: _onMessage,
      onUnregistered: _onUnregistered,
      onRegistrationFailed: _onRegistrationFailed);
  }

  void _onAccountsChanged() {
    unawaited(_registerNewAccounts());
  }

  /// Register each account not yet registered, where its server offers Web Push.
  ///
  /// UnifiedPush expects registrations to be renewed at every startup.
  /// Each prompts a call to [_onNewEndpoint].
  Future<void> _registerNewAccounts() async {
    final globalStore = await ZulipBinding.instance.getGlobalStore();
    _registeredAccountIds.retainAll(globalStore.accountIds);
    final newAccounts = globalStore.accounts
      .where((account) => !_registeredAccountIds.contains(account.id))
      .toList();
    if (newAccounts.isEmpty) return;
    // Before any await, so a store change meanwhile can't register them twice.
    _registeredAccountIds.addAll(newAccounts.map((account) => account.id));

    if (!await _ensureDistributor()) return;
    for (final account in newAccounts) {
      await _register(globalStore, account);
    }
  }

  Future<bool> _ensureDistributor() async {
    final unifiedPush = ZulipBinding.instance.unifiedPush;
    final hasDistributor = await unifiedPush.getDistributor() != null
      || await unifiedPush.tryUseCurrentOrDefaultDistributor();
    distributorMissing.value = !hasDistributor;
    return hasDistributor;
  }

  Future<void> _register(GlobalStore globalStore, Account account) async {
    final connection = globalStore.apiConnectionFromAccount(account);
    final WebPushConfig config;
    try {
      config = await getWebPushConfig(connection);
    } catch (e) {
      // Most likely an ordinary Zulip server, without Consort's Web Push.
      assert(debugLog('web push unavailable for account ${account.id}: $e'));
      return;
    } finally {
      connection.close();
    }
    if (!config.webPushEnabled) return;

    try {
      await ZulipBinding.instance.unifiedPush.register(
        account.id.toString(), const [], null, config.vapidPublicKey);
    } catch (e) {
      assert(debugLog('web push registration failed for account ${account.id}: $e'));
    }
  }

  Future<void> _onNewEndpoint(PushEndpoint endpoint, String instance) async {
    final keys = endpoint.pubKeySet;
    if (keys == null) {
      // The server only sends encrypted pushes, so it can't use this.
      // Distributors give keys whenever we register with a VAPID key,
      // as we always do.
      return; // TODO(log)
    }

    final globalStore = await ZulipBinding.instance.getGlobalStore();
    final account = _accountForInstance(globalStore, instance);
    if (account == null) {
      // Logged out since registering; stop the distributor pushing for it.
      await ZulipBinding.instance.unifiedPush.unregister(instance);
      return;
    }

    final connection = globalStore.apiConnectionFromAccount(account);
    try {
      await addWebPushSubscription(connection,
        endpoint: endpoint.url, p256dh: keys.pubKey, auth: keys.auth);
      _endpoints[account.id] = endpoint.url;
    } catch (e) {
      // TODO(log)
    } finally {
      connection.close();
    }
  }

  Future<void> _onMessage(PushMessage message, String instance) async {
    if (!message.decrypted) return; // TODO(log)

    final WebPushPayload payload;
    try {
      payload = WebPushPayload.fromJson(
        jsonDecode(utf8.decode(message.content)) as Map<String, dynamic>);
    } catch (e) {
      return; // TODO(log)
    }

    final globalStore = await ZulipBinding.instance.getGlobalStore();
    final account = _accountForInstance(globalStore, instance);
    // As with FCM, don't show notifications for a logged-out account.
    if (account == null) return;

    await NotificationDisplayManager.onWebPushPayload(payload, account);
  }

  void _onUnregistered(String instance) {
    // The distributor dropped the registration, perhaps at the user's request.
    // Pushes to the old endpoint now fail, and the server forgets it when they do.
    final accountId = int.tryParse(instance);
    if (accountId == null) return;
    _endpoints.remove(accountId);
  }

  void _onRegistrationFailed(FailedReason reason, String instance) {
    assert(debugLog('web push registration failed for instance $instance: $reason'));
  }

  static Account? _accountForInstance(GlobalStore globalStore, String instance) {
    final accountId = int.tryParse(instance);
    return accountId == null ? null : globalStore.getAccount(accountId);
  }

  /// Stop notifications for [account], which is being logged out.
  ///
  /// [connection] must be for [account].
  Future<void> unregister(Account account, ApiConnection connection) async {
    if (defaultTargetPlatform != TargetPlatform.android) return;
    _registeredAccountIds.remove(account.id);
    final endpoint = _endpoints.remove(account.id);
    try {
      await ZulipBinding.instance.unifiedPush.unregister(account.id.toString());
      // Without the endpoint, the server keeps the subscription until pushing
      // to it fails, which it will once the distributor has dropped it.
      if (endpoint != null) {
        await removeWebPushSubscription(connection, endpoint: endpoint);
      }
    } catch (e) {
      // TODO(log)
    }
  }
}
