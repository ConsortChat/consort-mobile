import 'dart:async';

import 'package:app_settings/app_settings.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../api/model/consort.dart';
import '../api/route/consort.dart' as api;
import '../generated/l10n/zulip_localizations.dart';
import '../host/android_calls.g.dart';
import '../model/binding.dart';
import '../model/consort.dart';
import 'dialog.dart';
import 'page.dart';
import 'store.dart';

/// On Android, request the microphone and camera permissions for a call.
///
/// Returns false if the user chose to go grant blocked permissions in settings
/// instead of joining now.
Future<bool> _requestCallPermissions(BuildContext context) async {
  if (defaultTargetPlatform != TargetPlatform.android) return true;

  // The Jitsi SDK requests these itself when it needs them.  But if one is
  // blocked, Android shows no request, and the call silently lacks it.
  final permissions = await ZulipBinding.instance.androidCallsHost
    .requestCallPermissions();
  if (permissions.microphone != CallPermissionStatus.blocked
      && permissions.camera != CallPermissionStatus.blocked) {
    return true;
  }

  if (!context.mounted) return false;
  final zulipLocalizations = ZulipLocalizations.of(context);
  final dialog = showSuggestedActionDialog(context: context,
    title: zulipLocalizations.permissionsNeededTitle,
    message: zulipLocalizations.permissionsDeniedCall,
    actionButtonText: zulipLocalizations.permissionsNeededOpenSettings,
    cancelButtonText: zulipLocalizations.permissionsNeededJoinCallAnyway);
  if (await dialog.result == true) {
    unawaited(AppSettings.openAppSettings());
    return false;
  }
  return true;
}

Future<void> joinConsortCall(BuildContext context, {
  required int? channelId,
  required List<int>? userIds,
  required int? loungeRoomId,
  required String subject,
}) async {
  final store = PerAccountStoreWidget.of(context);
  try {
    if (!await _requestCallPermissions(context)) return;
    final call = await api.createJitsiCall(store.connection,
      channelId: channelId,
      userIds: userIds,
      loungeRoomId: loungeRoomId);
    await ZulipBinding.instance.joinJitsiCall(call.url, subject: subject);
    if (loungeRoomId != null) {
      store.consort.clearOwnKnock(loungeRoomId);
    }
  } catch (error) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      // skip-i18n: Consort extension UI is not yet upstream-localized.
      content: Text('Could not join call: $error')));
  }
}

class ConsortCallButton extends StatelessWidget {
  const ConsortCallButton({
    super.key,
    required this.channelId,
    required this.userIds,
    required this.loungeRoomId,
    required this.subject,
    this.compact = false,
  });

  final int? channelId;
  final List<int>? userIds;
  final int? loungeRoomId;
  final String subject;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    void onPressed() {
      unawaited(joinConsortCall(context,
        channelId: channelId,
        userIds: userIds,
        loungeRoomId: loungeRoomId,
        subject: subject));
    }
    if (compact) {
      return IconButton(
        icon: const Icon(Icons.call),
        // skip-i18n: Consort extension UI is not yet upstream-localized.
        tooltip: 'Join call',
        onPressed: onPressed);
    }
    return FilledButton.icon(
      onPressed: onPressed,
      icon: const Icon(Icons.call),
      // skip-i18n: Consort extension UI is not yet upstream-localized.
      label: const Text('Join call'));
  }
}

class ConsortOccupancyStrip extends StatelessWidget {
  const ConsortOccupancyStrip({super.key, required this.occupancy});

  final CallOccupancy occupancy;

  @override
  Widget build(BuildContext context) {
    if (!occupancy.active) return const SizedBox.shrink();
    return Row(mainAxisSize: MainAxisSize.min, children: [
      const Icon(Icons.graphic_eq, size: 16, color: Colors.green),
      const SizedBox(width: 4),
      Flexible(child: Text(
        occupancy.occupants.isEmpty
          // skip-i18n: Consort extension UI is not yet upstream-localized.
          ? 'Call is open'
          : occupancy.occupants.map((occupant) => occupant.name).join(', '),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: Theme.of(context).textTheme.bodySmall)),
    ]);
  }
}

class VoiceChannelPage extends StatefulWidget {
  const VoiceChannelPage({super.key, required this.channelId});

  final int channelId;

  static AccountRoute<void> buildRoute({
    required BuildContext context,
    required int channelId,
  }) => MaterialAccountWidgetRoute(
    context: context,
    page: VoiceChannelPage(channelId: channelId));

  @override
  State<VoiceChannelPage> createState() => _VoiceChannelPageState();
}

class _VoiceChannelPageState extends State<VoiceChannelPage> {
  ConsortCallStore? _calls;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final calls = PerAccountStoreWidget.of(context).consort;
    if (identical(calls, _calls)) return;
    _calls?.removeListener(_changed);
    _calls?.stopPolling();
    _calls = calls
      ..addListener(_changed)
      ..startPolling();
  }

  void _changed() => setState(() {});

  @override
  void dispose() {
    _calls?.removeListener(_changed);
    _calls?.stopPolling();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final store = PerAccountStoreWidget.of(context);
    final channel = store.subscriptions[widget.channelId]
      ?? store.streams[widget.channelId];
    final occupancy = store.consort.occupancyByChannel[widget.channelId];
    return Scaffold(
      appBar: AppBar(title: Text(channel?.name ?? 'Voice channel')), // skip-i18n
      body: Center(child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.graphic_eq, size: 64),
          const SizedBox(height: 16),
          if (occupancy != null) ConsortOccupancyStrip(occupancy: occupancy)
          else const Text('Nobody is in the call yet'), // skip-i18n
          const SizedBox(height: 24),
          ConsortCallButton(
            channelId: widget.channelId,
            userIds: null,
            loungeRoomId: null,
            subject: channel?.name ?? 'Voice channel'), // skip-i18n
        ]))));
  }
}

class LoungePage extends StatefulWidget {
  const LoungePage({super.key, required this.channelId});

  final int channelId;

  static AccountRoute<void> buildRoute({
    required BuildContext context,
    required int channelId,
  }) => MaterialAccountWidgetRoute(
    context: context,
    page: LoungePage(channelId: channelId));

  @override
  State<LoungePage> createState() => _LoungePageState();
}

class _LoungePageState extends State<LoungePage> {
  ConsortCallStore? _calls;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final calls = PerAccountStoreWidget.of(context).consort;
    if (identical(calls, _calls)) return;
    _calls?.removeListener(_changed);
    _calls?.stopPolling();
    _calls = calls
      ..addListener(_changed)
      ..startPolling();
  }

  void _changed() => setState(() {});

  @override
  void dispose() {
    _calls?.removeListener(_changed);
    _calls?.stopPolling();
    super.dispose();
  }

  Future<void> _createRoom() async {
    final draft = await showDialog<({String name, bool isPrivate})>(
      context: context,
      builder: (context) => const _CreateRoomDialog());
    if (draft == null || !mounted) return;
    final store = PerAccountStoreWidget.of(context);
    try {
      final room = await api.createLoungeRoom(store.connection,
        channelId: widget.channelId,
        name: draft.name,
        isPrivate: draft.isPrivate);
      store.consort.upsertRoom(room);
      if (!mounted) return;
      await joinConsortCall(context,
        channelId: null,
        userIds: null,
        loungeRoomId: room.id,
        subject: room.name);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Could not create room: $error'))); // skip-i18n
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = PerAccountStoreWidget.of(context);
    final channel = store.subscriptions[widget.channelId]
      ?? store.streams[widget.channelId];
    final rooms = store.consort.roomsForChannel(widget.channelId);
    final canCreateRooms = channel?.canCreateRoomsGroup == null
      || store.selfInGroupSetting(channel!.canCreateRoomsGroup!);
    return Scaffold(
      appBar: AppBar(title: Text(channel?.name ?? 'Lounge')), // skip-i18n
      floatingActionButton: canCreateRooms
        ? FloatingActionButton.extended(
            onPressed: _createRoom,
            icon: const Icon(Icons.add),
            label: const Text('Create room')) // skip-i18n
        : null,
      body: RefreshIndicator(
        onRefresh: () => store.consort.refreshRooms(channelId: widget.channelId),
        child: rooms.isEmpty
          ? ListView(children: const [SizedBox(height: 160), Center(
              child: Text('No rooms are open. Create one to get started.'))]) // skip-i18n
          : ListView.builder(
              padding: const EdgeInsets.only(bottom: 96),
              itemCount: rooms.length,
              itemBuilder: (context, index) =>
                _LoungeRoomCard(room: rooms[index]))));
  }
}

class _LoungeRoomCard extends StatelessWidget {
  const _LoungeRoomCard({required this.room});

  final LoungeRoom room;

  Future<void> _knock(BuildContext context) async {
    final store = PerAccountStoreWidget.of(context);
    try {
      await api.knockOnLoungeRoom(store.connection, roomId: room.id);
      store.consort.recordOwnKnock(room.id);
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Could not knock: $error'))); // skip-i18n
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = PerAccountStoreWidget.of(context);
    final occupancy = store.consort.occupancyByLoungeRoom[room.id];
    final knockers = store.consort.knockersByRoom[room.id] ?? [];
    return Card(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(room.isPrivate ? Icons.lock : Icons.meeting_room),
            const SizedBox(width: 8),
            Expanded(child: Text(room.name,
              style: Theme.of(context).textTheme.titleMedium)),
            if (room.canAdminister) IconButton(
              icon: const Icon(Icons.settings),
              tooltip: 'Room settings', // skip-i18n
              onPressed: () => showDialog<void>(context: context,
                builder: (context) => _RoomSettingsDialog(room: room))),
          ]),
          if (occupancy != null) ...[
            const SizedBox(height: 8),
            ConsortOccupancyStrip(occupancy: occupancy),
          ],
          if (room.waitingForDoorman) const Padding(
            padding: EdgeInsets.only(top: 8),
            child: Text('Waiting for a doorman')), // skip-i18n
          if (room.canAdminister && knockers.isNotEmpty) ...[
            const Divider(height: 24),
            ...knockers.map((knocker) => _KnockerTile(
              roomId: room.id, knocker: knocker)),
          ],
          const SizedBox(height: 12),
          Align(alignment: Alignment.centerRight, child: switch ((
            room.canJoin,
            room.canKnock,
            store.consort.knockedRoomIds.contains(room.id),
          )) {
            (true, _, _) => ConsortCallButton(
              channelId: null,
              userIds: null,
              loungeRoomId: room.id,
              subject: room.name),
            (false, true, false) => OutlinedButton.icon(
              onPressed: () => _knock(context),
              icon: const Icon(Icons.front_hand),
              label: const Text('Knock')), // skip-i18n
            (false, _, true) => const Text('Knock sent'), // skip-i18n
            _ => const Text('Private room'), // skip-i18n
          }),
        ])));
  }
}

class _KnockerTile extends StatelessWidget {
  const _KnockerTile({required this.roomId, required this.knocker});

  final int roomId;
  final LoungeKnocker knocker;

  @override
  Widget build(BuildContext context) {
    final store = PerAccountStoreWidget.of(context);
    final user = knocker.userId == null ? null : store.getUser(knocker.userId!);
    final name = user?.fullName ?? knocker.guestName ?? 'Guest'; // skip-i18n
    return Row(children: [
      const Icon(Icons.person_outline),
      const SizedBox(width: 8),
      Expanded(child: Text(name)),
      TextButton(
        onPressed: () async {
          try {
            await api.admitToLoungeRoom(store.connection,
              roomId: roomId,
              userId: knocker.userId,
              guestKnockId: knocker.guestKnockId);
            store.consort.removeKnocker(roomId, knocker);
          } catch (error) {
            if (!context.mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text('Could not admit guest: $error'))); // skip-i18n
          }
        },
        child: const Text('Admit')), // skip-i18n
    ]);
  }
}

class _CreateRoomDialog extends StatefulWidget {
  const _CreateRoomDialog();

  @override
  State<_CreateRoomDialog> createState() => _CreateRoomDialogState();
}

class _CreateRoomDialogState extends State<_CreateRoomDialog> {
  final controller = TextEditingController();
  bool isPrivate = false;

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Create a room'), // skip-i18n
    content: Column(mainAxisSize: MainAxisSize.min, children: [
      TextField(
        controller: controller,
        autofocus: true,
        onChanged: (_) => setState(() {}),
        decoration: const InputDecoration(labelText: 'Room name')), // skip-i18n
      CheckboxListTile(
        contentPadding: EdgeInsets.zero,
        title: const Text('Private room'), // skip-i18n
        value: isPrivate,
        onChanged: (value) => setState(() => isPrivate = value ?? false)),
    ]),
    actions: [
      TextButton(onPressed: () => Navigator.pop(context),
        child: const Text('Cancel')), // skip-i18n
      FilledButton(
        onPressed: controller.text.trim().isEmpty
          ? null
          : () => Navigator.pop(context,
              (name: controller.text.trim(), isPrivate: isPrivate)),
        child: const Text('Create')), // skip-i18n
    ]);
}

class _RoomSettingsDialog extends StatefulWidget {
  const _RoomSettingsDialog({required this.room});

  final LoungeRoom room;

  @override
  State<_RoomSettingsDialog> createState() => _RoomSettingsDialogState();
}

class _RoomSettingsDialogState extends State<_RoomSettingsDialog> {
  late bool isPrivate = widget.room.isPrivate;
  late bool usersCanKnock = widget.room.knockableByUsers;
  late bool guestsCanKnock = widget.room.knockableByGuests;
  late final invitedUsersController = TextEditingController(
    text: widget.room.invitedUserIds.join(', '));
  bool saving = false;

  @override
  void dispose() {
    invitedUsersController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => saving = true);
    final store = PerAccountStoreWidget.of(context);
    try {
      final room = await api.updateLoungeRoom(store.connection,
        roomId: widget.room.id,
        isPrivate: isPrivate,
        knockableByUsers: usersCanKnock,
        knockableByGuests: guestsCanKnock,
        invitedUserIds: invitedUsersController.text.trim().isEmpty
          ? []
          : invitedUsersController.text.split(',')
              .map((value) => int.parse(value.trim())).toList());
      store.consort.upsertRoom(room);
      if (mounted) Navigator.pop(context);
    } catch (error) {
      if (!mounted) return;
      setState(() => saving = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Could not save settings: $error'))); // skip-i18n
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.room.name),
    content: Column(mainAxisSize: MainAxisSize.min, children: [
      CheckboxListTile(
        contentPadding: EdgeInsets.zero,
        title: const Text('Private room'), // skip-i18n
        value: isPrivate,
        onChanged: saving ? null : (value) => setState(() => isPrivate = value!)),
      CheckboxListTile(
        contentPadding: EdgeInsets.zero,
        title: const Text('Members can knock'), // skip-i18n
        value: usersCanKnock,
        onChanged: saving ? null : (value) => setState(() => usersCanKnock = value!)),
      CheckboxListTile(
        contentPadding: EdgeInsets.zero,
        title: const Text('Guests can knock'), // skip-i18n
        value: guestsCanKnock,
        onChanged: saving ? null : (value) => setState(() => guestsCanKnock = value!)),
      TextField(
        controller: invitedUsersController,
        enabled: !saving,
        keyboardType: TextInputType.number,
        decoration: const InputDecoration(
          labelText: 'Invited user IDs',
          helperText: 'Separate multiple IDs with commas')), // skip-i18n
    ]),
    actions: [
      TextButton(onPressed: saving ? null : () => Navigator.pop(context),
        child: const Text('Cancel')), // skip-i18n
      FilledButton(onPressed: saving ? null : _save,
        child: const Text('Save')), // skip-i18n
    ]);
}
