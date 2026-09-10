// API models for Consort's authenticated Jitsi and lounge-room extensions.

class JitsiCall {
  JitsiCall({
    required this.url,
    required this.room,
    required this.tenant,
    required this.epochToken,
  });

  final Uri url;
  final String room;
  final String tenant;
  final String? epochToken;

  factory JitsiCall.fromJson(Map<String, dynamic> json) => JitsiCall(
    url: Uri.parse(json['url'] as String),
    room: json['room'] as String,
    tenant: json['tenant'] as String,
    epochToken: json['epoch_token'] as String?,
  );
}

class CallOccupant {
  CallOccupant({required this.name, required this.userId});

  final String name;
  final int? userId;

  factory CallOccupant.fromJson(Map<String, dynamic> json) => CallOccupant(
    name: json['name'] as String,
    userId: (json['user_id'] as num?)?.toInt(),
  );
}

class CallOccupancy {
  CallOccupancy({
    required this.streamId,
    required this.userIds,
    required this.loungeRoomId,
    required this.active,
    required this.count,
    required this.occupants,
    required this.drifted,
  });

  final int? streamId;
  final List<int>? userIds;
  final int? loungeRoomId;
  final bool active;
  final int count;
  final List<CallOccupant> occupants;
  final bool drifted;

  factory CallOccupancy.fromJson(Map<String, dynamic> json) => CallOccupancy(
    streamId: (json['stream_id'] as num?)?.toInt(),
    userIds: (json['user_ids'] as List<dynamic>?)
      ?.map((value) => (value as num).toInt()).toList(),
    loungeRoomId: (json['lounge_room_id'] as num?)?.toInt(),
    active: json['active'] as bool,
    count: (json['count'] as num).toInt(),
    occupants: (json['occupants'] as List<dynamic>)
      .map((value) => CallOccupant.fromJson(value as Map<String, dynamic>))
      .toList(),
    drifted: json['drifted'] as bool? ?? false,
  );
}

class CallOccupancyResult {
  CallOccupancyResult({required this.rooms, required this.closedChannelIds});

  final List<CallOccupancy> rooms;
  final List<int> closedChannelIds;

  factory CallOccupancyResult.fromJson(Map<String, dynamic> json) =>
    CallOccupancyResult(
      rooms: (json['rooms'] as List<dynamic>)
        .map((value) => CallOccupancy.fromJson(value as Map<String, dynamic>))
        .toList(),
      closedChannelIds: (json['closed_channel_ids'] as List<dynamic>? ?? [])
        .map((value) => (value as num).toInt()).toList(),
    );
}

class LoungeRoom {
  LoungeRoom({
    required this.id,
    required this.channelId,
    required this.name,
    required this.creatorId,
    required this.isPrivate,
    required this.canJoin,
    required this.canKnock,
    required this.canAdminister,
    required this.waitingForDoorman,
    required this.knockableByUsers,
    required this.knockableByGuests,
    required this.invitedUserIds,
  });

  final int id;
  final int channelId;
  final String name;
  final int? creatorId;
  final bool isPrivate;
  final bool canJoin;
  final bool canKnock;
  final bool canAdminister;
  final bool waitingForDoorman;
  final bool knockableByUsers;
  final bool knockableByGuests;
  final List<int> invitedUserIds;

  factory LoungeRoom.fromJson(Map<String, dynamic> json) => LoungeRoom(
    id: (json['id'] as num).toInt(),
    channelId: (json['channel_id'] as num).toInt(),
    name: json['name'] as String,
    creatorId: (json['creator_id'] as num?)?.toInt(),
    isPrivate: json['is_private'] as bool,
    canJoin: json['can_join'] as bool,
    canKnock: json['can_knock'] as bool,
    canAdminister: json['can_administer'] as bool,
    waitingForDoorman: json['waiting_for_doorman'] as bool,
    knockableByUsers: json['knockable_by_users'] as bool,
    knockableByGuests: json['knockable_by_guests'] as bool,
    invitedUserIds: (json['invited_user_ids'] as List<dynamic>? ?? [])
      .map((value) => (value as num).toInt()).toList(),
  );
}

class LoungeRoomsResult {
  LoungeRoomsResult({required this.rooms});

  final List<LoungeRoom> rooms;

  factory LoungeRoomsResult.fromJson(Map<String, dynamic> json) =>
    LoungeRoomsResult(
      rooms: (json['rooms'] as List<dynamic>)
        .map((value) => LoungeRoom.fromJson(value as Map<String, dynamic>))
        .toList(),
    );
}

class CreateLoungeRoomResult {
  CreateLoungeRoomResult({required this.room});

  final LoungeRoom room;

  factory CreateLoungeRoomResult.fromJson(Map<String, dynamic> json) =>
    CreateLoungeRoomResult(
      room: LoungeRoom.fromJson(json['room'] as Map<String, dynamic>),
    );
}
