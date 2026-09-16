# Android distribution variants

Consort's Android app is built in two variants,
as Gradle product flavors:

| Variant | Distribution | Dart entrypoint | Android push transports |
| --- | --- | --- | --- |
| `play` | Google Play | `lib/main.dart` | Firebase Cloud Messaging (FCM), plus UnifiedPush |
| `fdroid` | F-Droid | `lib/main_fdroid.dart` | UnifiedPush only |

Both variants are releases of the same app and use the Android application ID
`chat.consort.mobile`.
They share the same version name and version code for a given release.

iOS has no flavors; it builds from `lib/main.dart`, with FCM.

## Building

Android builds must always name a flavor.
(There is no default flavor:
a `default-flavor` in `pubspec.yaml` would apply to iOS too,
where the Xcode project has no matching scheme.)

For Google Play, and for development:

```
flutter run --flavor play
flutter build appbundle --release --flavor play
```

For F-Droid, in a checkout dedicated to that build:

```
tools/prepare-fdroid
flutter build apk --release --flavor fdroid -t lib/main_fdroid.dart
```

## How Firebase is kept out of the F-Droid build

F-Droid's main repository does not accept non-free dependencies
such as the Firebase and Google Play services libraries used for FCM.
Skipping Firebase initialization at runtime is not sufficient:
the F-Droid dependency graph and APK must not contain those libraries.
Three things ensure that:

- **Dart code.**
  Shared code reaches FCM only through
  `ZulipBinding.remotePushNotifications` (see `lib/model/binding.dart`),
  never through package:firebase_messaging.
  The Firebase implementation is in `lib/notifications/firebase.dart`,
  which only `lib/main.dart` imports.
  `lib/main_fdroid.dart` supplies no implementation,
  so the F-Droid build receives notifications only through UnifiedPush,
  and requests Android's notification permission itself
  (which Firebase does in the Play build).

- **Dependencies.**
  Flutter has no per-flavor dependencies,
  so `tools/prepare-fdroid` removes `firebase_core` and `firebase_messaging`
  from `pubspec.yaml` and runs `flutter pub get`.
  That drops them and their own dependencies from `pubspec.lock`,
  keeping every other package at its locked version;
  the script checks that.
  The result is not committed:
  the F-Droid build is reproducible from the committed `pubspec.lock`.

- **Checks.**
  The Gradle build of any `fdroid` variant fails
  if its runtime classpath contains `com.google.firebase`
  or `com.google.android.gms` artifacts;
  see `android/app/build.gradle`.
  CI builds the F-Droid APK that way,
  and also scans its code for classes in those packages.

The Play build keeps UnifiedPush alongside FCM,
so users can choose a distributor without changing install source.

## The Jitsi SDK

Jitsi's released Android SDK can't be used:
it depends on Jitsi's build of `react-native-google-signin`,
and through it on Google Play services,
and it is a prebuilt binary from Jitsi's own Maven repository.

Instead, both variants use an SDK built from source
vendored in `third_party/jitsi-meet`,
without Google sign-in, live streaming, Share video (YouTube),
or upstream's other non-free modules (Amplitude, Giphy).
Run `tools/build-jitsi-sdk` once before building for Android,
and again after changing that source;
it needs Node.js 24+.
See `third_party/jitsi-meet/README.consort.md`.

## Dependency verification

Gradle checks every dependency it downloads
against SHA-256 checksums committed in
`android/gradle/verification-metadata.xml` for the app, and
`third_party/jitsi-meet/android/gradle/verification-metadata.xml`
for the Jitsi SDK.
A build fails if a dependency is missing from the file
or doesn't match its checksum.
The Gradle wrappers check the Gradle distribution
against `distributionSha256Sum` the same way.

The app trusts Flutter's engine artifacts (group `io.flutter`)
without checksums:
their versions already name a Flutter engine commit,
and CI builds with the latest Flutter from its main channel,
so their checksums would change with every Flutter commit.

After a change that adds or upgrades Android dependencies,
such as upgrading pub packages with Android code,
record the new checksums:

```
tools/gradle --write-verification-metadata sha256 \
  :app:lintPlayDebug :app:assemblePlayRelease :app:bundlePlayRelease \
  -x :app:preFdroidReleaseBuild -x :app:preFdroidDebugBuild
tools/build-jitsi-sdk --write-verification-metadata
```

and, in a checkout prepared with `tools/prepare-fdroid`:

```
tools/gradle --write-verification-metadata sha256 :app:assembleFdroidRelease
```

The `-x` options skip the checks that the F-Droid variant is free of
Firebase, which fail in a checkout that still has it.
Gradle runs those checks here although it doesn't when Flutter
invokes the same build; they are checks, not build steps,
and the F-Droid variant's dependencies get recorded either way.

Gradle adds entries but doesn't remove old ones.
Check each addition in the diff before committing:
it should be a dependency the change was meant to bring in.

Gradle records the AAPT2 build tool only for the platform it ran on,
so both files list `com.android.tools.build:aapt2`
for Linux, macOS and Windows.
After an upgrade of the Android Gradle plugin changes that version,
add the other platforms' jars by hand,
with checksums of the jars under
https://dl.google.com/android/maven2/com/android/tools/build/aapt2/ .

## Remaining work

- Review the remaining prebuilt artifacts against F-Droid's policy.
  They come from Maven Central, pinned by checksum:
  React Native (`com.facebook.react:react-android`), Hermes,
  and Jitsi's build of WebRTC (`org.jitsi:webrtc`).
- Confirm on devices that the Play APK receives FCM notifications,
  and that the F-Droid APK asks for the notification permission
  on Android 13+ and receives UnifiedPush notifications
  while the app is stopped.
- Add F-Droid metadata (in fdroiddata) once a tagged source release builds.
  The recipe should run `tools/prepare-fdroid` and the build command above,
  rather than maintain a downstream patch.
  It will need to pin the Flutter version,
  since this app tracks Flutter's `main` channel;
  see the `environment` section of `pubspec.yaml`.
- Choose and document the signing arrangement; see below.

## Package identity and signing

Using `chat.consort.mobile` for both variants gives Consort one canonical
Android identity and prevents both variants from being installed side by side.
Android accepts an update only when it is signed with the same key as the
installed app.
Before publishing either variant, choose and document the Play App Signing and
F-Droid signing arrangement.
If the stores use different signing keys, users must stay on one distribution
channel or uninstall the app before switching, which removes local app data.

See the F-Droid
[Inclusion Policy](https://f-droid.org/en/docs/Inclusion_Policy/)
for the repository's current dependency requirements.
