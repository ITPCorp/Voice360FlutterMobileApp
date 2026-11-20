import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:itp_voice/services/app_wake/full_screen_calls.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('dismissal lasts 24 hours and settings access is rechecked',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    const channel = MethodChannel('voice360/app_wake');
    var granted = false;
    var settingsVisits = 0;
    final messenger = tester.binding.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'fsiAllowed') return granted;
      expect(call.method, 'openFsiSettings');
      settingsVisits++;
      return true;
    });
    addTearDown(() {
      messenger.setMockMethodCallHandler(channel, null);
      Get.reset();
    });
    await tester.pumpWidget(const GetMaterialApp(home: Scaffold()));
    final access = FullScreenCalls.instance;
    await access.check();
    expect(access.allowed.value, false);
    expect(find.text('Open settings'), findsNothing);
    final first = access.check(mayPrompt: () => true);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Not now'));
    await tester.pumpAndSettle();
    await first;
    await access.check(mayPrompt: () => true);
    expect(find.text('Open settings'), findsNothing);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(
        'full_screen_calls_prompt_ms',
        DateTime.now()
            .subtract(const Duration(hours: 25))
            .millisecondsSinceEpoch);
    final next = access.check(mayPrompt: () => true);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Open settings'));
    await tester.pumpAndSettle();
    await next;
    expect(settingsVisits, 1);
    granted = true;
    await access.check(mayPrompt: () => true);
    await tester.pumpAndSettle();
    expect(access.allowed.value, true);
    expect(find.text('Full-screen incoming calls are on.'), findsOneWidget);
  });
}
