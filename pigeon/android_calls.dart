import 'package:pigeon/pigeon.dart';

// To rebuild this pigeon's output after editing this file,
// run `tools/check pigeon --fix`.
@ConfigurePigeon(PigeonOptions(
  dartOut: 'lib/host/android_calls.g.dart',
  kotlinOut: 'android/app/src/main/kotlin/chat/consort/mobile/AndroidCalls.g.kt',
  kotlinOptions: KotlinOptions(
    package: 'chat.consort.mobile',
    // One error class is already generated in AndroidNotifications.g.kt ,
    // so avoid generating another one, preventing duplicate classes under
    // the same namespace.
    includeErrorClass: false)))

enum CallPermissionStatus {
  granted,

  /// The user denied the permission,
  /// but Android may still show a request for it.
  denied,

  /// The permission is denied, and Android won't show a request for it,
  /// e.g. because the user has denied it before.
  /// The user can grant it only in the app's system settings.
  ///
  /// Android doesn't distinguish this from a request that the user dismissed
  /// without choosing, so that case is reported as blocked too.
  ///
  /// See: https://developer.android.com/training/permissions/requesting#handle-denial
  blocked,
}

class CallPermissions {
  CallPermissions({required this.microphone, required this.camera});

  /// The status of `RECORD_AUDIO`.
  final CallPermissionStatus microphone;

  /// The status of `CAMERA`.
  final CallPermissionStatus camera;
}

@HostApi()
abstract class AndroidCallsHostApi {
  /// Request the `RECORD_AUDIO` and `CAMERA` runtime permissions,
  /// for those the app doesn't already have,
  /// and return the resulting status of each.
  ///
  /// If there is no activity to show the request from,
  /// this reports each missing permission as denied, without asking.
  ///
  /// See: https://developer.android.com/training/permissions/requesting
  @async
  CallPermissions requestCallPermissions();
}
