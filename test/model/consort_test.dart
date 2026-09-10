import 'package:checks/checks.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zulip/api/model/consort.dart';
import 'package:zulip/api/model/events.dart';

import '../example_data.dart' as eg;
import 'binding.dart';

LoungeRoom room({required int id}) => LoungeRoom(
  id: id,
  channelId: 9,
  name: 'Room $id',
  creatorId: 1,
  isPrivate: false,
  canJoin: true,
  canKnock: false,
  canAdminister: true,
  waitingForDoorman: false,
  knockableByUsers: true,
  knockableByGuests: false,
  invitedUserIds: const [],
);

CallOccupancy occupancy({required int roomId, required bool active}) =>
  CallOccupancy(
    streamId: null,
    userIds: null,
    loungeRoomId: roomId,
    active: active,
    count: 0,
    occupants: const [],
    drifted: false,
  );

void main() {
  TestZulipBinding.ensureInitialized();

  test('active zero-person lounge remains open; inactive closes it', () async {
    final store = eg.store(initialSnapshot: eg.initialSnapshot(
      serverJitsiJwtEnabled: true));
    addTearDown(store.dispose);
    store.consort.upsertRoom(room(id: 4));

    await store.handleEvent(JitsiOccupancyEvent(
      id: 1, room: occupancy(roomId: 4, active: true)));
    check(store.consort.roomsForChannel(9).map((room) => room.id))
      .deepEquals([4]);
    check(store.consort.occupancyByLoungeRoom[4]).isNotNull();

    await store.handleEvent(JitsiOccupancyEvent(
      id: 2, room: occupancy(roomId: 4, active: false)));
    check(store.consort.roomsForChannel(9)).isEmpty();
    check(store.consort.occupancyByLoungeRoom[4]).isNull();
  });

  test('DM occupancy key is insensitive to user order', () async {
    final store = eg.store(initialSnapshot: eg.initialSnapshot(
      serverJitsiJwtEnabled: true));
    addTearDown(store.dispose);
    await store.handleEvent(JitsiOccupancyEvent(
      id: 1,
      room: CallOccupancy(
        streamId: null,
        userIds: const [8, 2],
        loungeRoomId: null,
        active: true,
        count: 1,
        occupants: const [],
        drifted: false)));
    check(store.consort.occupancyForDm([2, 8])).isNotNull();
  });
}
