import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import 'licenses.dart';
import 'log.dart';
import 'model/binding.dart';
import 'notifications/receive.dart';
import 'notifications/web_push.dart';
import 'widgets/app.dart';
import 'widgets/share.dart';

// This library defines the Dart entrypoint function for the
// headless Flutter engine used in our iOS "NotificationService" app extension.
// Importing it here causes it to be included in the build.
// ignore: unused_import
import 'notifications/ios_service.dart';

void main(List<String> args) {
  if (args.contains(WebPushService.kBackgroundEngineArg)) {
    _mainInBackground();
    return;
  }
  mainInit();
  runApp(const ZulipApp());
}

/// What [main] does in the headless engine the UnifiedPush plugin starts
/// to deliver a push while the app isn't running; see [WebPushService].
void _mainInBackground() {
  assert(() {
    debugLogEnabled = true;
    return true;
  }());
  WidgetsFlutterBinding.ensureInitialized();
  LiveZulipBinding.ensureInitialized();
  WebPushService.instance.startInBackground();
}

/// Everything [main] does short of [runApp].
///
/// This is useful for setup in Patrol-based integration tests.
void mainInit() {
  assert(() {
    debugLogEnabled = true;
    return true;
  }());
  LicenseRegistry.addLicense(additionalLicenses);
  WidgetsFlutterBinding.ensureInitialized();
  LiveZulipBinding.ensureInitialized();
  NotificationService.instance.start();
  ShareService.start();
}
