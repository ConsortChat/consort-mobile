import 'main_common.dart' as common;

/// The entrypoint for the F-Droid build of the app.
///
/// This build has no Firebase; it receives notifications only by UnifiedPush.
/// See docs/android-distribution.md.
void main(List<String> args) {
  common.runMain(args, remotePushNotifications: null);
}
