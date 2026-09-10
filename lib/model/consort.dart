import 'dart:async';

import 'package:flutter/foundation.dart';

import '../api/model/consort.dart';
import '../api/model/events.dart';
import '../api/route/consort.dart' as api;
import 'store.dart';

class LoungeKnocker {
  LoungeKnocker({
    required this.userId,
    required this.guestKnockId,
    required this.guestName,
  });

  final int? userId;
  final String? guestKnockId;
  final String? guestName;
}

/// Live call and lounge state for one Zulip account.
class ConsortCallStore extends PerAccountStoreBase with ChangeNotifier {
  ConsortCallStore({
    required super.core,
    required this.enabled,
  });

  final bool enabled;

  final Map<int, CallOccupancy> occupancyByChannel = {};
  final Map<int, CallOccupancy> occupancyByLoungeRoom = {};
  final Map<String, CallOccupancy> occupancyByDm = {};
  final Map<int, List<LoungeKnocker>> knockersByRoom = {};
  final Set<int> knockedRoomIds = {};
  final Set<int> closedChannelIds = {};

  List<LoungeRoom> loungeRooms = [];
  Object? lastError;
  bool isRefreshing = false;

  Timer? _pollTimer;
  int _pollUsers = 0;
  final List<Timer> _knockExpiryTimers = [];

  List<LoungeRoom> roomsForChannel(int channelId) => loungeRooms
    .where((room) => room.channelId == channelId).toList(growable: false);

  CallOccupancy? occupancyForDm(List<int> userIds) =>
    occupancyByDm[_dmKey(userIds)];

  void startPolling() {
    if (!enabled) return;
    _pollUsers++;
    if (_pollTimer != null) return;
    unawaited(refresh());
    _pollTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      unawaited(refresh());
    });
  }

  void stopPolling() {
    if (!enabled || _pollUsers == 0) return;
    _pollUsers--;
    if (_pollUsers > 0) return;
    _pollTimer?.cancel();
    _pollTimer = null;
  }

  Future<void> refresh() async {
    if (!enabled || isRefreshing) return;
    isRefreshing = true;
    notifyListeners();
    try {
      final results = await Future.wait([
        api.getJitsiOccupancyAll(connection),
        api.getLoungeRooms(connection, channelId: null),
      ]);
      _replaceOccupancy(results[0] as CallOccupancyResult);
      loungeRooms = (results[1] as LoungeRoomsResult).rooms;
      lastError = null;
    } catch (error) {
      lastError = error;
    } finally {
      isRefreshing = false;
      notifyListeners();
    }
  }

  Future<void> refreshRooms({required int channelId}) async {
    if (!enabled) return;
    try {
      final result = await api.getLoungeRooms(connection, channelId: channelId);
      loungeRooms = [
        ...loungeRooms.where((room) => room.channelId != channelId),
        ...result.rooms,
      ];
      lastError = null;
      notifyListeners();
    } catch (error) {
      lastError = error;
      notifyListeners();
    }
  }

  void handleEvent(Event event) {
    switch (event) {
      case JitsiOccupancyEvent():
        _putOccupancy(event.room);
        notifyListeners();
      case LoungeRoomsChangedEvent():
        unawaited(refreshRooms(channelId: event.channelId));
      case LoungeKnockEvent():
        final knocker = LoungeKnocker(
          userId: event.userId,
          guestKnockId: event.guestKnockId,
          guestName: event.guestName,
        );
        knockersByRoom.putIfAbsent(event.roomId, () => []).add(knocker);
        final timer = Timer(const Duration(minutes: 2), () {
          knockersByRoom[event.roomId]?.remove(knocker);
          if (knockersByRoom[event.roomId]?.isEmpty ?? false) {
            knockersByRoom.remove(event.roomId);
          }
          notifyListeners();
        });
        _knockExpiryTimers.add(timer);
        notifyListeners();
      default:
        throw ArgumentError.value(event, 'event', 'not a Consort event');
    }
  }

  void recordOwnKnock(int roomId) {
    knockedRoomIds.add(roomId);
    notifyListeners();
  }

  void clearOwnKnock(int roomId) {
    knockedRoomIds.remove(roomId);
    notifyListeners();
  }

  void removeKnocker(int roomId, LoungeKnocker knocker) {
    knockersByRoom[roomId]?.remove(knocker);
    if (knockersByRoom[roomId]?.isEmpty ?? false) {
      knockersByRoom.remove(roomId);
    }
    notifyListeners();
  }

  void upsertRoom(LoungeRoom room) {
    loungeRooms = [
      ...loungeRooms.where((candidate) => candidate.id != room.id),
      room,
    ];
    notifyListeners();
  }

  void _replaceOccupancy(CallOccupancyResult result) {
    occupancyByChannel.clear();
    occupancyByLoungeRoom.clear();
    occupancyByDm.clear();
    closedChannelIds
      ..clear()
      ..addAll(result.closedChannelIds);
    for (final room in result.rooms) {
      _putOccupancy(room);
    }
  }

  void _putOccupancy(CallOccupancy room) {
    final channelId = room.streamId;
    final loungeRoomId = room.loungeRoomId;
    final userIds = room.userIds;
    if (channelId != null) {
      if (room.active) {
        occupancyByChannel[channelId] = room;
      } else {
        occupancyByChannel.remove(channelId);
      }
    } else if (loungeRoomId != null) {
      // A zero-person active lounge remains visible; active=false closes it.
      if (room.active) {
        occupancyByLoungeRoom[loungeRoomId] = room;
      } else {
        occupancyByLoungeRoom.remove(loungeRoomId);
        loungeRooms = loungeRooms
          .where((candidate) => candidate.id != loungeRoomId).toList();
      }
    } else if (userIds != null) {
      final key = _dmKey(userIds);
      if (room.active) {
        occupancyByDm[key] = room;
      } else {
        occupancyByDm.remove(key);
      }
    }
  }

  static String _dmKey(List<int> userIds) {
    final sorted = [...userIds]..sort();
    return sorted.join(',');
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    for (final timer in _knockExpiryTimers) {
      timer.cancel();
    }
    super.dispose();
  }
}
