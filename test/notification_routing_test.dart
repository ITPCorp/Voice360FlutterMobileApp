import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:itp_voice/controllers/base_screen_controller.dart';
import 'package:itp_voice/controllers/chat_controller.dart';
import 'package:itp_voice/locator.dart';
import 'package:itp_voice/screens/chat_screen.dart';
import 'package:itp_voice/services/demo_mode_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:itp_voice/controllers/voicemails_controller.dart';
import 'package:itp_voice/models/get_voice_mails_response_model/result.dart';
import 'package:itp_voice/routes.dart';
import 'package:itp_voice/services/notification_destination.dart';
import 'package:itp_voice/services/push_service.dart';

class _Home extends BaseScreenController {
  @override
  // Keep SIP, network and device plugins out of this navigation test.
  // ignore: must_call_super
  void onInit() {}
  @override
  void onReady() {}
}

class _Mailbox extends VoiceMailsController {
  @override
  // Keep SIP, network and device plugins out of this navigation test.
  // ignore: must_call_super
  void onInit() {}
  @override
  void onReady() {}
}

void main() {
  test('server payloads retain the exact ID and receiving line', () {
    for (final data in [
      {
        'metadata':
            "{'message_thread_id': 73, 'to_phone_number': '+12025550111', 'note': \"O'Brien\"}"
      },
      {'metadata': '{"conversation_id":"73","to_number":"+12025550111"}'},
      {'message_thread_pk': 73, 'msg_id': 5, 'to_phone_number': '+12025550111'},
    ]) {
      final target = NotificationDestination.parse(data)!;
      expect(target.id, '73');
      expect(target.number, '+12025550111');
    }
    expect(NotificationDestination.parse({'title': 'New voicemail'})?.screen,
        NotificationScreen.voicemail);
    expect(NotificationDestination.parse({'title': 'New SMS Message'})?.screen,
        NotificationScreen.messages);
    expect(
        NotificationDestination.parse(
            {'type': 'voice360_call', 'thread_id': 73}),
        isNull);
    expect(
        NotificationDestination.parse(
                {'type': 'voicemail', 'msg_id': 'a', 'message_thread_id': 73})!
            .id,
        'a');
  });

  testWidgets(
      'a second SMS tap replaces the open conversation and its messages',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    await DemoModeService.instance.setEnabled(true);
    addTearDown(() => DemoModeService.instance.setEnabled(false));
    addTearDown(Get.reset);
    setupLocator();
    addTearDown(locator.reset);
    Get.put<SharedPreferences>(prefs);
    Get.put<BaseScreenController>(_Home());
    final push = PushService();
    await tester.pumpWidget(GetMaterialApp(
      initialRoute: Routes.BASE_SCREEN_ROUTE,
      getPages: [
        GetPage(name: Routes.BASE_SCREEN_ROUTE, page: () => const Scaffold()),
        GetPage(name: Routes.CHAT_SCREEN_ROUTE, page: () => const ChatScreen()),
      ],
    ));
    await tester.pumpAndSettle();
    push.flushPendingNavigation();

    for (final id in ['9001', '9002']) {
      push.handleTap({
        'message_thread_id': id,
        'to_phone_number': DemoModeService.demoFromNumber
      });
      await tester.pumpAndSettle();
      expect(ChatController.visibleThreadId, id);
      expect(find.text(id == '9001' ? 'Alex Chen' : 'Jordan Rivera'),
          findsWidgets);
    }

    Get.back();
    await tester.pumpAndSettle();
    expect(ChatController.visible, isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
      'cold launch, replacement conversation, missed call and exact voicemail',
      (tester) async {
    final push = PushService();
    final home = Get.put<BaseScreenController>(_Home());
    final mailbox = Get.put<VoiceMailsController>(_Mailbox());
    mailbox.voiceMails = [
      VoiceMails(msgId: '2', pk: 1),
      VoiceMails(msgId: 'second', pk: 2)
    ];
    push.handleTap({'conversation_id': '40', 'to_number': '111'});
    await tester.pumpWidget(GetMaterialApp(initialRoute: '/', getPages: [
      GetPage(name: '/', page: () => const Scaffold(body: Text('home'))),
      GetPage(
          name: Routes.CHAT_SCREEN_ROUTE,
          page: () => Builder(
              builder: (c) => Scaffold(
                  body: Text(
                      'thread ${(ModalRoute.of(c)!.settings.arguments as List).first}')))),
      GetPage(
          name: Routes.VOICE_MAIL_DETAILS_ROUTE,
          page: () => Builder(
              builder: (c) => Scaffold(
                  body: Text(
                      (ModalRoute.of(c)!.settings.arguments as VoiceMails)
                          .msgId!)))),
    ]));
    await tester.pumpAndSettle();
    expect(find.text('home'), findsOneWidget);
    push.flushPendingNavigation();
    await tester.pumpAndSettle();
    expect(find.text('thread 40'), findsOneWidget);
    push.handleTap({'message_thread_id': 81, 'to_number': '222'});
    await tester.pumpAndSettle();
    expect(find.text('thread 81'), findsOneWidget);
    expect(find.text('thread 40'), findsNothing);
    push.handleTap({'type': 'missed_call', 'caller_name': 'Alex'});
    await tester.pumpAndSettle();
    expect(home.dialTab, 1);
    expect(home.currentTab.value, 0);
    expect(home.missedCall.value?.caller, 'Alex');
    push.handleTap({'type': 'voicemail', 'voicemail_id': 2});
    await tester.pumpAndSettle();
    expect(find.text('second'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    Get.reset();
  });
}
