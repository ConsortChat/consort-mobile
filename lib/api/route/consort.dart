import '../core.dart';
import '../model/consort.dart';

Future<JitsiCall> createJitsiCall(ApiConnection connection, {
  required int? channelId,
  required List<int>? userIds,
  required int? loungeRoomId,
  String? epochToken,
  bool rotate = false,
}) {
  assert([channelId, userIds, loungeRoomId].where((value) => value != null).length == 1);
  final rawEpochToken = epochToken == null ? null : RawParameter(epochToken);
  return connection.post('createJitsiCall', JitsiCall.fromJson,
    'calls/jitsi/create', {
      'stream_id': ?channelId,
      'user_ids': ?userIds,
      'lounge_room_id': ?loungeRoomId,
      'epoch_token': ?rawEpochToken,
      if (rotate) 'rotate': true,
    });
}

Future<CallOccupancyResult> getJitsiOccupancyAll(ApiConnection connection) =>
  connection.get('getJitsiOccupancyAll', CallOccupancyResult.fromJson,
    'calls/jitsi/occupancy_all', null);

Future<LoungeRoomsResult> getLoungeRooms(ApiConnection connection, {
  required int? channelId,
}) => connection.get('getLoungeRooms', LoungeRoomsResult.fromJson,
  'lounges/rooms', {'stream_id': ?channelId});

Future<LoungeRoom> createLoungeRoom(ApiConnection connection, {
  required int channelId,
  required String name,
  required bool isPrivate,
}) async {
  final result = await connection.post('createLoungeRoom',
    CreateLoungeRoomResult.fromJson, 'lounges/$channelId/rooms', {
      'name': RawParameter(name),
      'is_private': isPrivate,
    });
  return result.room;
}

Future<LoungeRoom> updateLoungeRoom(ApiConnection connection, {
  required int roomId,
  String? name,
  bool? isPrivate,
  bool? knockableByUsers,
  bool? knockableByGuests,
  List<int>? invitedUserIds,
}) async {
  final rawName = name == null ? null : RawParameter(name);
  final result = await connection.patch('updateLoungeRoom',
    CreateLoungeRoomResult.fromJson, 'lounges/rooms/$roomId', {
      'name': ?rawName,
      'is_private': ?isPrivate,
      'knockable_by_users': ?knockableByUsers,
      'knockable_by_guests': ?knockableByGuests,
      'invited_user_ids': ?invitedUserIds,
    });
  return result.room;
}

Future<void> knockOnLoungeRoom(ApiConnection connection, {
  required int roomId,
}) => connection.post('knockOnLoungeRoom', (_) {},
  'lounges/rooms/$roomId/knock', null);

Future<void> admitToLoungeRoom(ApiConnection connection, {
  required int roomId,
  required int? userId,
  required String? guestKnockId,
}) {
  assert((userId == null) != (guestKnockId == null));
  final rawGuestKnockId = guestKnockId == null
    ? null : RawParameter(guestKnockId);
  return connection.post('admitToLoungeRoom', (_) {},
    'lounges/rooms/$roomId/admit', {
      'user_id': ?userId,
      'guest_knock_id': ?rawGuestKnockId,
    });
}
