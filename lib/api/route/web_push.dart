// API bindings for Consort's Web Push extension.
//
// The Consort server delivers push notifications itself, as Web Push
// (RFC 8030) encrypted to the subscriber (RFC 8291), rather than routing
// through Zulip's push bouncer and FCM/APNs.
//
// A subscription is just an endpoint URL plus the two keys the server
// encrypts to, so nothing here is browser-specific: the same endpoints
// serve a browser's PushManager subscription and one obtained from a
// UnifiedPush distributor on Android.

import '../core.dart';

/// The server's Web Push configuration.
class WebPushConfig {
  WebPushConfig({
    required this.webPushEnabled,
    required this.vapidPublicKey,
  });

  /// Whether the server has a VAPID keypair, and so can send Web Push at all.
  final bool webPushEnabled;

  /// The server's VAPID public key, to subscribe with.
  ///
  /// Empty when [webPushEnabled] is false.
  final String vapidPublicKey;

  factory WebPushConfig.fromJson(Map<String, dynamic> json) => WebPushConfig(
    webPushEnabled: json['web_push_enabled'] as bool,
    vapidPublicKey: json['vapid_public_key'] as String,
  );
}

/// Get whether this server sends Web Push, and the VAPID key to subscribe with.
Future<WebPushConfig> getWebPushConfig(ApiConnection connection) =>
  connection.get('getWebPushConfig', WebPushConfig.fromJson,
    'users/me/web_push_subscription', null);

/// Store, or refresh, a Web Push subscription for this user.
///
/// The server replaces any existing subscription with the same [endpoint],
/// so this is safe to call on every startup.
///
/// [p256dh] is the subscriber's P-256 public key and [auth] its auth secret,
/// each base64url-encoded without padding, as in RFC 8291.
Future<void> addWebPushSubscription(ApiConnection connection, {
  required String endpoint,
  required String p256dh,
  required String auth,
}) => connection.post('addWebPushSubscription', (_) {},
  'users/me/web_push_subscription', {
    'endpoint': RawParameter(endpoint),
    'p256dh': RawParameter(p256dh),
    'auth': RawParameter(auth),
  });

/// Drop a Web Push subscription.
Future<void> removeWebPushSubscription(ApiConnection connection, {
  required String endpoint,
}) => connection.delete('removeWebPushSubscription', (_) {},
  'users/me/web_push_subscription', {
    'endpoint': RawParameter(endpoint),
  });
