import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:itp_voice/controllers/call_screen_controller.dart';
import 'package:itp_voice/screens/call_screen.dart';

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
