# Consort features in the Flutter client

This client understands the API extensions from
[`Dyslectric/Consort`](https://github.com/Dyslectric/Consort) and the
`lounges` branch of
[`Dyslectric/zulip-meet-integration`](https://github.com/Dyslectric/zulip-meet-integration).
An ordinary Zulip server remains compatible: all Consort fields default to the
ordinary text-channel behavior, and call UI is gated by
`server_jitsi_jwt_enabled`.

## Implemented

- `text`, `voice`, and `lounge` channel kinds, including their sidebar icons
  and navigation behavior.
- Authenticated, conversation-scoped call creation through
  `POST /api/v1/calls/jitsi/create` for channels, DMs, and lounge rooms.
- Native Android/iOS calls through `jitsi_meet_flutter_sdk`. The SDK provides
  its native in-call UI and platform minimization/Picture-in-Picture behavior.
- Live call occupancy from the initial occupancy endpoint and
  `jitsi_occupancy` events. Channel rows show the active roster; voice and
  lounge pages show the corresponding room roster.
- Lounge-room listing and creation, public/private rooms, join and knock
  states, authenticated-user and guest knock events, doorman admission, room
  privacy/knock settings, explicit invited-user IDs, and client-side handling
  of the `can_create_rooms_group` permission.
- Correct ephemeral-room handling: an active room with zero occupants remains
  open, while an `active: false` occupancy update closes it locally.
- Android Web Push notifications through a user-installed UnifiedPush
  distributor, including delivery while the app is stopped and subscription
  cleanup on logout.
- Server-controlled moderator status, access checks, JWT lifetime, call roster
  messages, and room cleanup continue to be enforced by the Consort server.

## Platform configuration

- Android already targets API 26 (the Jitsi SDK requires 24). The app manifest
  contains the merge directive required by the SDK.
- iOS now targets 15.1 and declares camera and microphone usage. The Jitsi SDK
  supports Android and iOS, not the Flutter web/desktop targets.

## Follow-up parity work

- Replace the temporary English Consort strings with generated ARB
  localizations.
- Add a people picker for room invitations instead of the current comma-
  separated user-ID field.
- Add signed-out guest-link handling (`create_as_guest`) and screen-sharing
  broadcast-extension setup on iOS.
- Add in-app status and setup UI for choosing or installing a UnifiedPush
  distributor when Android cannot select one automatically.
- If a native SDK event exposes speaker activity reliably, mirror Consort web's
  speaking rings in the Flutter sidebar. The current sidebar indicates live
  occupancy and names; the native in-call UI owns speaking indication.
