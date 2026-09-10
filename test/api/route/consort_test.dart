import 'dart:convert';

import 'package:checks/checks.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_test/flutter_test.dart';
import 'package:zulip/api/route/consort.dart';

import '../fake_api.dart';
import '../../stdlib_checks.dart';

void main() {
  test('create channel call sends conversation scope', () {
    return FakeApiConnection.with_((connection) async {
      connection.prepare(json: {
        'url': 'https://meet.example.test/acme/general?jwt=token',
        'room': 'general',
        'tenant': 'acme',
        'epoch_token': 'epoch',
      });
      final result = await createJitsiCall(connection,
        channelId: 42, userIds: null, loungeRoomId: null);
      check(result.room).equals('general');
      check(connection.takeRequests()).single.isA<http.Request>()
        ..method.equals('POST')
        ..url.path.equals('/api/v1/calls/jitsi/create')
        ..bodyFields.deepEquals({'stream_id': '42'});
    });
  });

  test('create DM call JSON-encodes recipient IDs', () {
    return FakeApiConnection.with_((connection) async {
      connection.prepare(json: {
        'url': 'https://meet.example.test/acme/dm?jwt=token',
        'room': 'dm',
        'tenant': 'acme',
        'epoch_token': null,
      });
      await createJitsiCall(connection,
        channelId: null, userIds: [2, 5], loungeRoomId: null);
      check(connection.takeRequests()).single.isA<http.Request>()
        .bodyFields.deepEquals({'user_ids': jsonEncode([2, 5])});
    });
  });

  test('create lounge room preserves raw name', () {
    return FakeApiConnection.with_((connection) async {
      connection.prepare(json: {'room': {
        'id': 4,
        'channel_id': 9,
        'name': 'Kitchen table',
        'creator_id': 2,
        'is_private': false,
        'can_join': true,
        'can_knock': false,
        'can_administer': true,
        'waiting_for_doorman': false,
        'knockable_by_users': true,
        'knockable_by_guests': false,
      }});
      await createLoungeRoom(connection,
        channelId: 9, name: 'Kitchen table', isPrivate: false);
      check(connection.takeRequests()).single.isA<http.Request>()
        ..url.path.equals('/api/v1/lounges/9/rooms')
        ..bodyFields.deepEquals({
          'name': 'Kitchen table',
          'is_private': 'false',
        });
    });
  });
}
