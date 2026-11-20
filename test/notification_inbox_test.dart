import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:itp_voice/services/notification_destination.dart';
import 'package:itp_voice/services/notification_inbox.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('voice360/notification_inbox');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final rows = {
    'missed-a': {'type': 'missed_call'},
    'missed-b': {'type': 'missed_call'},
    'thread-a': {'metadata': "{'message_thread_id': 11}"},
    'thread-a-local': '{"message_thread_id":"11"}',
    'thread-b': {'conversation_id': 12},
    'recording-a': {'voicemail_msg_id': '11'},
    'recording-a-pk': {'voicemail_message_pk': 96},
    'recording-b': {'voicemail_message_pk': 11},
    'legacy': {'title': 'New SMS Message'},
    'active-call': {'type': 'voice360_call'},
  };
  late List<Object?> removed;
  setUp(() {
    removed = [];
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'active') {
        return rows.entries
            .map((e) => {'key': e.key, 'payload': e.value})
            .toList();
      }
      expect(call.method, 'remove');
      removed.addAll(call.arguments as List);
      return null;
    });
  });
  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  test('Recent removes every missed call and keeps the ongoing call', () async {
    await NotificationInbox.recent();
    expect(removed, ['missed-a', 'missed-b']);
  });
  test('opening a thread removes its local and remote cards only', () async {
    await NotificationInbox.thread('11');
    expect(removed, ['thread-a', 'thread-a-local']);
  });
  test('opening a voicemail matches the message ID and its database key',
      () async {
    await NotificationInbox.voicemail('11', 96);
    expect(removed, ['recording-a', 'recording-a-pk']);
  });
  test('unresolved destinations do not erase alerts', () async {
    await NotificationInbox.thread(null);
    await NotificationInbox.voicemail(null, null);
    expect(removed, isEmpty);
  });
  test('Android tags carry the same identity used for navigation', () {
    for (final field in [
      'message_thread_id',
      'voicemail_msg_id',
      'voicemail_message_pk'
    ]) {
      final dest = NotificationDestination.parse({field: '12'})!;
      final tag = NotificationInbox.androidTag(dest)!;
      final parsed = NotificationDestination.parse(
          jsonDecode(tag.substring('voice360.inbox:'.length)))!;
      expect(parsed.screen, dest.screen);
      expect(parsed.recordPk, dest.recordPk);
      expect(parsed.id, dest.id);
    }
  });
}
