import 'package:checks/checks.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zulip/api/web_push.dart';

void main() {
  group('WebPushPayload.fromJson', () {
    test('add', () {
      final payload = WebPushPayload.fromJson({
        'type': 'add',
        'message_id': 123,
        'title': 'Alice',
        'body': 'Hello there',
      });
      check(payload).isA<WebPushAddPayload>();
      final add = payload as WebPushAddPayload;
      check(add.messageId).equals(123);
      check(add.title).equals('Alice');
      check(add.body).equals('Hello there');
    });

    test('remove', () {
      final payload = WebPushPayload.fromJson({
        'type': 'remove',
        'message_ids': [123, 456],
      });
      check(payload).isA<WebPushRemovePayload>();
      check((payload as WebPushRemovePayload).messageIds).deepEquals([123, 456]);
    });

    test('unexpected type', () {
      check(() => WebPushPayload.fromJson({'type': 'unexpected'}))
        .throws<FormatException>();
    });

    test('malformed known type', () {
      check(() => WebPushPayload.fromJson({
        'type': 'add',
        'message_id': '123',
        'title': 'Alice',
        'body': 'Hello there',
      })).throws<TypeError>();
    });
  });
}
