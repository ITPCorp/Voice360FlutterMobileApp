import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:itp_voice/controllers/call_screen_controller.dart';
import 'package:itp_voice/screens/call_screen.dart';
import 'package:itp_voice/services/app_wake/call_wake_service.dart';
import 'package:itp_voice/services/app_wake/wake_call.dart';
import 'package:itp_voice/widgets/on_call_bar.dart';

class _CallController extends CallScreenController {
  int muteTaps = 0;
  int endTaps = 0;

  @override
  // No SIP or device session is needed to exercise the controls.
  // ignore: must_call_super
  void onInit() {}

  @override
  void onReady() {}

  @override
  void muteAudio() => muteTaps++;

  @override
  void handleHangup({bool goBack = false}) => endTaps++;
}

void main() {
  testWidgets(
      'connecting shows the push caller and allows hangup without a SIP call',
      (tester) async {
    var ended = false;
    await tester.pumpWidget(MaterialApp(
        home: ConnectingCallScreen(
      caller: 'Dev caller',
      hangup: () => ended = true,
    )));
    expect(find.text('Dev caller'), findsOneWidget);
    expect(find.text('Connecting…'), findsOneWidget);
    expect(find.text('In call'), findsNothing);
    expect(find.text('00:00'), findsNothing);
    expect(tester.getCenter(find.text('End call')).dx,
        tester.getCenter(find.byType(Scaffold)).dx);
    await tester.tap(find.text('End call'));
    expect(ended, isTrue);
  });

  testWidgets(
      'a cold wake covers the existing route before any SIP call exists',
      (tester) async {
    final wake = CallWakeService.instance;
    final c = WakeCall(const WakePush(
        action: 'ring',
        callId: 'cold-test',
        uuid: 'cold-test',
        callerName: 'Dev caller',
        receivedAtMs: 1000));
    final nav = GlobalKey<NavigatorState>();
    addTearDown(() => wake.connectingCall.value = null);
    await tester.pumpWidget(MaterialApp(
        navigatorKey: nav,
        builder: (_, child) => OnCallBarHost(child: child!),
        home: const Scaffold(body: Text('Home'))));
    final navigator = nav.currentState;
    wake.connectingCall.value = c;
    await tester.pump();
    expect(find.text('Connecting…'), findsOneWidget);
    expect(find.text('Dev caller'), findsOneWidget);
    expect(find.text('End call').hitTestable(), findsOneWidget);
    expect(nav.currentState, same(navigator));
    wake.connectingCall.value = null;
    await tester.pump();
    expect(find.text('Connecting…'), findsNothing);
    expect(nav.currentState, same(navigator));
  });
  testWidgets('the control label and circle each invoke the same single action',
      (tester) async {
    final call = _CallController();
    Get.put<CallScreenController>(call);
    addTearDown(Get.reset);
    await tester.pumpWidget(GetMaterialApp(home: CallScreen()));
    await tester.pumpAndSettle();
    final label = find.text('Mute');
    await tester.ensureVisible(label);
    await tester.tap(label);
    await tester.pumpAndSettle();
    expect(call.muteTaps, 1);
    await tester.tap(find.byIcon(Icons.mic_rounded));
    await tester.pumpAndSettle();
    expect(call.muteTaps, 2);

    call.active.routes.assignAll(['earpiece', 'speaker', 'bluetooth']);
    await tester.pumpAndSettle();
    final routeLabel = find.text('Phone');
    await tester.ensureVisible(routeLabel);
    await tester.tap(routeLabel);
    await tester.pumpAndSettle();
    expect(find.text('Bluetooth'), findsOneWidget);
    Get.back();
    await tester.pumpAndSettle();
    final end = find.text('End call');
    await tester.ensureVisible(end);
    await tester.tap(end);
    await tester.pumpAndSettle();
    expect(call.endTaps, 1);
    await tester.pumpWidget(const SizedBox());
  });
}
