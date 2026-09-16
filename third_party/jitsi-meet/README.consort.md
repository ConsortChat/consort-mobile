# Jitsi Meet, vendored for Consort

This directory holds the source of
[jitsi-meet](https://github.com/jitsi/jitsi-meet)
at tag `mobile-sdk-13.1.1`
(commit `1a308a6873098c038cf264f3d8f5378bb975601b`),
with the Consort changes listed below.
From it, `tools/build-jitsi-sdk` builds the Jitsi Meet SDK for Android
and the React Native modules it uses.

Consort builds the SDK itself so that the app's Android builds contain
no Google Play services or other non-free code, as F-Droid requires;
see `docs/android-distribution.md`.

## Building

`tools/build-jitsi-sdk` runs `npm ci` here,
then builds and publishes the SDK and its React Native modules
to the Maven repository `third_party/jitsi-sdk-maven` (not committed).
`packages/jitsi_meet_flutter_sdk`,
the Jitsi Meet Flutter plugin vendored from pub.dev version 13.1.1,
takes the SDK from there instead of from Jitsi's Maven repository.

Android builds of the app fail with a message to run the script
if the repository is missing.
Rerun the script after changing anything here.

iOS builds still use Jitsi's released `JitsiMeetSDK` pod.
There the app hides live streaming and Share video with feature flags
(see `joinJitsiCall` in `lib/model/binding.dart`).

## Omitted from upstream

These aren't needed to build the Android SDK:
`ios/`, `tests/`, `android/fastlane/`,
`metadata/`, `twa/`, and `readme-img1.png`.
The Jitsi Meet app in `android/app/` is replaced by a stand-in; see below.

Kept from upstream, though the SDK build doesn't need them,
and worth a look before an F-Droid submission:
`android/keystores/` (upstream's app-signing setup)
and the Gradle wrapper jar `android/gradle/wrapper/gradle-wrapper.jar`,
the tree's only binary file.

## Consort changes

Deletions aside, changes are marked with `Consort:` comments.

- Removed Google sign-in:
  the `@react-native-google-signin/google-signin` dependency,
  the native Google API client and sign-in button,
  and the loading of its native package in `ReactHostHolder.java`.
- Removed live streaming (to YouTube, with Google sign-in)
  from the mobile UI: its overflow-menu button, dialogs, and screen.
- Removed Share video from the mobile UI:
  its overflow-menu button, and YouTube playback
  (the `react-native-youtube-iframe` dependency and its player).
  A shared video from a direct URL still plays;
  a YouTube video shared from the web app doesn't show.
- Build in libre mode (`LIBRE_BUILD`) by default,
  which also leaves out the Amplitude analytics and Giphy modules.
- Replace the Jitsi Meet app (`android/app/`) with an empty stand-in
  application project, and remove the Google services and Crashlytics
  Gradle plugins, which only the app used.
  Several React Native modules' builds need an application project
  in the build; the stand-in has none of the app's code.
- Version the published React Native modules with a fixed `-consort`
  qualifier instead of a timestamp, so builds are reproducible.
- Pin `org.jitsi:webrtc` to 124.0.0;
  `react-native-webrtc` asks for any `124.+`.
  Drop the JitPack repository, which nothing uses.
- Check Gradle dependencies against the checksums in
  `android/gradle/verification-metadata.xml`,
  and the Gradle distribution against `distributionSha256Sum`
  in `android/gradle/wrapper/gradle-wrapper.properties`.
- Exclude Gradle's state directories from the JS bundle task's inputs;
  on Windows, Gradle can't read its own lock files there.
- Keep remote video off Samsung Exynos hardware decoders
  (`JitsiVideoDecoderFactory.java`), so it is decoded in software
  on Pixel and Samsung Exynos phones.
  With them, a Pixel 9 Pro XL joining a call where a screen share
  was already running showed the share as a black tile.

## Upgrading

1. Replace this directory's contents with the new upstream tag,
   minus the omitted paths above, keeping this file.
2. Reapply the changes above (compare this directory's git history),
   and run `npm install` to update `package-lock.json`.
3. Update the SDK version in `tools/build-jitsi-sdk` and
   `packages/jitsi_meet_flutter_sdk/android/build.gradle`,
   and upgrade `packages/jitsi_meet_flutter_sdk` to the matching release.
4. Build with `tools/build-jitsi-sdk --write-verification-metadata`,
   and review the checksums it adds to
   `android/gradle/verification-metadata.xml`;
   see "Dependency verification" in `docs/android-distribution.md`.
