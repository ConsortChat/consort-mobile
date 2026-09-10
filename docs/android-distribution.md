# Android distribution variants

This document records the planned split between the Google Play and F-Droid
builds of Consort.
The split is not implemented yet.

Both variants are releases of the same app and use the Android application ID
`chat.consort.mobile`.
They share the same version name and version code for a given release.

| Variant | Distribution | Android push transports |
| --- | --- | --- |
| `play` | Google Play | Firebase Cloud Messaging (FCM), plus UnifiedPush |
| `fdroid` | F-Droid | UnifiedPush only |

## Why the F-Droid build must differ

The app currently declares `firebase_core` and `firebase_messaging` as direct
dependencies in `pubspec.yaml`.
Firebase types and calls also appear in `lib/model/binding.dart`,
`lib/notifications/receive.dart`, and `lib/firebase_options.dart`.
Consequently, every Android build currently includes the Firebase Flutter
plugins and their Google dependencies, even when UnifiedPush handles delivery.

F-Droid's main repository does not permit non-free dependencies such as the
Firebase and Google Play services libraries used for FCM.
Skipping Firebase initialization at runtime is not sufficient:
the F-Droid dependency graph and APK must not contain those libraries.

## Required implementation

1. Add explicit `play` and `fdroid` Android product flavors.
   The release commands should identify both the Android flavor and its Dart
   entrypoint, for example:

   ```
   flutter build appbundle --release --flavor play -t lib/main_play.dart
   flutter build apk --release --flavor fdroid -t lib/main_fdroid.dart
   ```

2. Separate the notification implementations from the shared app code.
   Shared notification code must use Consort-owned message and transport
   interfaces rather than expose types from `firebase_core` or
   `firebase_messaging`.
   Play-only code should own Firebase initialization, FCM token registration,
   foreground delivery, and the FCM background entrypoint.
   F-Droid-only code should start UnifiedPush and must never initialize or
   register with Firebase.

3. Give the two builds separate Flutter dependency graphs.
   Flutter packages cannot be made conditional by an Android Gradle flavor,
   so adding flavors while retaining Firebase in the root `pubspec.yaml` would
   still produce a noncompliant F-Droid APK.
   Use either separate thin Flutter runner packages or a deterministic,
   checked-in prebuild transformation that produces an F-Droid manifest and
   lockfile without Firebase.
   Separate runner packages are preferred because CI can resolve and test both
   dependency graphs directly.

4. Keep UnifiedPush registration and cleanup shared where practical.
   The F-Droid build must continue to support delivery while the app is stopped,
   account-specific Web Push subscriptions, renewal at startup, and subscription
   deletion on logout.
   The Play build may retain UnifiedPush alongside FCM so users can choose a
   distributor without changing install source.

5. Add CI checks for both variants.
   The Play check must confirm FCM registration and foreground/background
   delivery still work.
   The F-Droid check must fail if its resolved packages, Gradle dependency tree,
   or APK contain Firebase, Google Play services, or other non-free artifacts.
   It must also exercise UnifiedPush registration, foreground delivery,
   background delivery, and logout cleanup.

6. Add F-Droid metadata only after the Firebase-free build is reproducible from
   a tagged source release.
   The metadata should invoke the checked-in F-Droid build path rather than
   maintaining an undocumented downstream patch.

## Package identity and signing

Using `chat.consort.mobile` for both variants gives Consort one canonical
Android identity and prevents both variants from being installed side by side.
Android accepts an update only when it is signed with the same key as the
installed app.
Before publishing either variant, choose and document the Play App Signing and
F-Droid signing arrangement.
If the stores use different signing keys, users must stay on one distribution
channel or uninstall the app before switching, which removes local app data.

## Completion criteria

The distribution split is complete when:

- both release commands build from a clean checkout;
- both APKs report `chat.consort.mobile` and the expected version;
- the Play APK receives FCM notifications;
- the F-Droid APK contains no Firebase or Google Play services code;
- the F-Droid APK receives UnifiedPush notifications with the app stopped;
- signing and cross-store update behavior are documented; and
- CI prevents Firebase from being reintroduced into the F-Droid artifact.

See the F-Droid
[Inclusion Policy](https://f-droid.org/en/docs/Inclusion_Policy/)
for the repository's current dependency requirements.
