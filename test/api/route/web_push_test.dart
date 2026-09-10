import 'package:checks/checks.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_test/flutter_test.dart';
import 'package:zulip/api/route/web_push.dart';

import '../fake_api.dart';
import '../../stdlib_checks.dart';

void main() {
  group('getWebPushConfig', () {
    test('enabled', () {
      return FakeApiConnection.with_((connection) async {
        connection.prepare(json: {
          'web_push_enabled': true,
          'vapid_public_key': 'BNcRdreALRFXTkOOUHK1EtK2wtaz5Ry4YfYCA_0QTpQtUbVlUls0VJXg7A8u-Ts1XbjhazAkj7I99e8QcYP7DkM',
        });
        final result = await getWebPushConfig(connection);
        check(result.webPushEnabled).isTrue();
        check(result.vapidPublicKey).startsWith('BNcRdreALRFXTkOOUHK1EtK2');
        check(connection.takeRequests()).single.isA<http.Request>()
          ..method.equals('GET')
          ..url.path.equals('/api/v1/users/me/web_push_subscription');
      });
    });

    test('disabled: key is empty, not absent', () {
      return FakeApiConnection.with_((connection) async {
        connection.prepare(json: {
          'web_push_enabled': false,
          'vapid_public_key': '',
        });
        final result = await getWebPushConfig(connection);
        check(result.webPushEnabled).isFalse();
        check(result.vapidPublicKey).equals('');
      });
    });
  });

  group('addWebPushSubscription', () {
    test('smoke', () {
      return FakeApiConnection.with_((connection) async {
        connection.prepare(json: {});
        await addWebPushSubscription(connection,
          endpoint: 'https://ntfy.example.test/UPqcpQxYzS6bH9',
          p256dh: 'BJ2xmvJ0h6nJVqLQ0sKz8jUXhVBqNC8oXxwWXhqPBhZ',
          auth: 'k8JV6sjdbhAi3TrqFVwzZg');
        check(connection.takeRequests()).single.isA<http.Request>()
          ..method.equals('POST')
          ..url.path.equals('/api/v1/users/me/web_push_subscription')
          // Sent raw: these are URLs and base64url, not JSON-encoded strings.
          ..bodyFields.deepEquals({
            'endpoint': 'https://ntfy.example.test/UPqcpQxYzS6bH9',
            'p256dh': 'BJ2xmvJ0h6nJVqLQ0sKz8jUXhVBqNC8oXxwWXhqPBhZ',
            'auth': 'k8JV6sjdbhAi3TrqFVwzZg',
          });
      });
    });
  });

  group('removeWebPushSubscription', () {
    test('smoke', () {
      return FakeApiConnection.with_((connection) async {
        connection.prepare(json: {});
        await removeWebPushSubscription(connection,
          endpoint: 'https://ntfy.example.test/UPqcpQxYzS6bH9');
        check(connection.takeRequests()).single.isA<http.Request>()
          ..method.equals('DELETE')
          ..url.path.equals('/api/v1/users/me/web_push_subscription')
          ..bodyFields.deepEquals({
            'endpoint': 'https://ntfy.example.test/UPqcpQxYzS6bH9',
          });
      });
    });
  });
}
