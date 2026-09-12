import 'package:checks/checks.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:zulip/host/android_calls.g.dart';
import 'package:zulip/widgets/consort.dart';

import '../api/fake_api.dart';
import '../example_data.dart' as eg;
import '../model/binding.dart';
import '../stdlib_checks.dart';
import 'dialog_checks.dart';
import 'test_app.dart';

void main() {
  TestZulipBinding.ensureInitialized();

  group('ConsortCallButton permissions', () {
    const appSettingsChannel = MethodChannel('com.spencerccf.app_settings/methods');

    late FakeApiConnection connection;
    late List<MethodCall> appSettingsCalls;

    Future<void> prepare(WidgetTester tester, {
      CallPermissionStatus microphone = CallPermissionStatus.granted,
      CallPermissionStatus camera = CallPermissionStatus.granted,
    }) async {
      addTearDown(testBinding.reset);
      final channel = eg.stream();
      await testBinding.globalStore.add(eg.selfAccount, eg.initialSnapshot(
        streams: [channel]));
      final store = await testBinding.globalStore.perAccount(eg.selfAccount.id);
      connection = store.connection as FakeApiConnection;
      testBinding.androidCallsHost.requestCallPermissionsResult =
        CallPermissions(microphone: microphone, camera: camera);

      appSettingsCalls = [];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        appSettingsChannel, (call) async {
          appSettingsCalls.add(call);
          return null;
        });
      addTearDown(() => tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(appSettingsChannel, null));

      await tester.pumpWidget(TestZulipApp(accountId: eg.selfAccount.id,
        child: ConsortCallButton(channelId: channel.streamId,
          userIds: null, loungeRoomId: null, subject: channel.name)));
      await tester.pump();
    }

    void prepareCreateCall() {
      connection.prepare(json: {
        'url': 'https://meet.example.test/acme/general?jwt=token',
        'room': 'general',
        'tenant': 'acme',
        'epoch_token': 'epoch',
      });
    }

    Future<void> tapJoin(WidgetTester tester) async {
      await tester.tap(find.text('Join call'));
      await tester.pump();
    }

    void checkJoined() {
      check(connection.takeRequests()).single.isA<http.Request>()
        ..method.equals('POST')
        ..url.path.equals('/api/v1/calls/jitsi/create');
      check(testBinding.takeJoinJitsiCallCalls()).single
        .has((call) => call.url.host, 'url.host').equals('meet.example.test');
    }

    void checkNotJoined() {
      check(connection.takeRequests()).isEmpty();
      check(testBinding.takeJoinJitsiCallCalls()).isEmpty();
    }

    Future<(Widget, Widget)> checkPermissionsDialog(WidgetTester tester) async {
      await tester.pump();
      return checkSuggestedActionDialog(tester,
        expectedTitle: 'Permissions needed',
        expectedMessage: 'To use your microphone and camera in calls, please grant Consort additional permissions in Settings.',
        expectedActionButtonText: 'Open settings',
        expectedCancelButtonText: 'Join anyway');
    }

    testWidgets('granted: join without dialog', (tester) async {
      await prepare(tester,
        microphone: CallPermissionStatus.granted,
        camera: CallPermissionStatus.granted);
      prepareCreateCall();
      await tapJoin(tester);
      await tester.pump(Duration.zero); // wait through API request
      check(testBinding.androidCallsHost.takeRequestCallPermissionsCallCount())
        .equals(1);
      checkNoDialog(tester);
      checkJoined();
    }, variant: TargetPlatformVariant.only(TargetPlatform.android));

    testWidgets('denied but not blocked: join without dialog', (tester) async {
      await prepare(tester,
        microphone: CallPermissionStatus.denied,
        camera: CallPermissionStatus.denied);
      prepareCreateCall();
      await tapJoin(tester);
      await tester.pump(Duration.zero); // wait through API request
      checkNoDialog(tester);
      checkJoined();
    }, variant: TargetPlatformVariant.only(TargetPlatform.android));

    testWidgets('blocked: open settings instead of joining', (tester) async {
      await prepare(tester, camera: CallPermissionStatus.blocked);
      await tapJoin(tester);
      final (actionButton, _) = await checkPermissionsDialog(tester);
      await tester.tap(find.byWidget(actionButton));
      await tester.pump();
      check(appSettingsCalls).single.has((call) => call.method, 'method')
        .equals('openSettings');
      checkNotJoined();
    }, variant: TargetPlatformVariant.only(TargetPlatform.android));

    testWidgets('blocked: join anyway', (tester) async {
      await prepare(tester, microphone: CallPermissionStatus.blocked);
      await tapJoin(tester);
      final (_, cancelButton) = await checkPermissionsDialog(tester);
      prepareCreateCall();
      await tester.tap(find.byWidget(cancelButton));
      await tester.pump(Duration.zero); // wait through API request
      check(appSettingsCalls).isEmpty();
      checkJoined();
    }, variant: TargetPlatformVariant.only(TargetPlatform.android));

    testWidgets('no permission request on iOS', (tester) async {
      await prepare(tester);
      prepareCreateCall();
      await tapJoin(tester);
      await tester.pump(Duration.zero); // wait through API request
      check(testBinding.androidCallsHost.takeRequestCallPermissionsCallCount())
        .equals(0);
      checkJoined();
    }, variant: TargetPlatformVariant.only(TargetPlatform.iOS));
  });
}
