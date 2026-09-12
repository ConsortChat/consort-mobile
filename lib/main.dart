import 'main_common.dart' as common;
import 'notifications/firebase.dart';

/// The entrypoint for the Google Play and iOS builds of the app.
///
/// For the F-Droid build, see lib/main_fdroid.dart.
void main(List<String> args) {
  common.runMain(args, remotePushNotifications: FirebaseRemotePushNotifications());
}

/// Everything [main] does short of starting the UI.
///
/// This is useful for setup in Patrol-based integration tests.
void mainInit() {
  common.mainInit(remotePushNotifications: FirebaseRemotePushNotifications());
}
