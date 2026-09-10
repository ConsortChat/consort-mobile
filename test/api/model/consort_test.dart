import 'package:checks/checks.dart';
import 'package:test/scaffolding.dart';
import 'package:zulip/api/model/consort.dart';
import 'package:zulip/api/model/events.dart';
import 'package:zulip/api/model/model.dart';

void main() {
  test('channel kind fields default for ordinary Zulip servers', () {
    final channel = ZulipStream.fromJson({
      'stream_id': 1,
      'name': 'general',
      'description': '',
      'rendered_description': '',
      'date_created': 1,
      'invite_only': false,
      'is_web_public': false,
      'history_public_to_subscribers': true,
    });
    check(channel.voiceVideoEnabled).isFalse();
    check(channel.textChatDisabled).isFalse();
    check(channel.isLounge).isFalse();
    check(channel.callDoorPolicy).equals('anarchy');
  });

  test('lounge room parses access and door state', () {
    final room = LoungeRoom.fromJson({
      'id': 4,
      'channel_id': 9,
      'name': 'Kitchen table',
      'creator_id': 2,
      'is_private': true,
      'can_join': false,
      'can_knock': true,
      'can_administer': false,
      'waiting_for_doorman': true,
      'knockable_by_users': true,
      'knockable_by_guests': false,
      'invited_user_ids': [5, 6],
    });
    check(room.id).equals(4);
    check(room.canKnock).isTrue();
    check(room.waitingForDoorman).isTrue();
    check(room.invitedUserIds).deepEquals([5, 6]);
  });

  test('jitsi occupancy event parses authenticated and guest occupants', () {
    final event = Event.fromJson({
      'id': 10,
      'type': 'jitsi_occupancy',
      'lounge_room_id': 7,
      'active': true,
      'count': 2,
      'occupants': [
        {'name': 'A', 'user_id': 3},
        {'name': 'Guest', 'user_id': null},
      ],
    });
    check(event).isA<JitsiOccupancyEvent>();
    final occupancy = (event as JitsiOccupancyEvent).room;
    check(occupancy.loungeRoomId).equals(7);
    check(occupancy.count).equals(2);
    check(occupancy.occupants.map((value) => value.userId))
      .deepEquals([3, null]);
  });

  test('lounge knock supports guest identity', () {
    final event = Event.fromJson({
      'id': 11,
      'type': 'lounge_knock',
      'room_id': 8,
      'guest_knock_id': 'guest-1',
      'guest_name': 'Visitor',
    });
    check(event).isA<LoungeKnockEvent>();
    final knock = event as LoungeKnockEvent;
    check(knock.userId).isNull();
    check(knock.guestKnockId).equals('guest-1');
    check(knock.guestName).equals('Visitor');
  });
}
