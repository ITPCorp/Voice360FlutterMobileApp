import 'package:flutter_test/flutter_test.dart';
import 'package:itp_voice/helpers/group_chat.dart';
import 'package:itp_voice/models/get_thread_messages_response_model/get_thread_messages_response_model.dart';

void main() {
  test('a generated contact displays its national number', () {
    expect(conversationName('+13052990233', 'Contact'), isNull);
    expect(conversationNumber('+13052990233'), '(305) 299-0233');
    expect(conversationName('Alex', 'Contact'), 'Alex Contact');
    expect(conversationNumber('+442079460000'), '+442079460000');
  });

  test('send, socket, refresh and disk copy represent the same instant', () {
    for (final (raw, offset) in [
      ('2026-11-20T16:05:00', '-05:00'),
      ('2026-07-20T15:05:00', '-04:00'),
    ]) {
      final wall = '${raw.substring(0, 10)}T11:05:00';
      final post = Messages.fromJson({'message_timestamp': raw}, rawUtc: true);
      final refreshed = Messages.fromJson({
        'message_timestamp': wall,
        'message_timestamp_utc': raw,
      });
      final websocket = Messages.fromPayload({'message_timestamp_utc': raw});
      final aware = Messages.fromJson({'message_timestamp': '$wall$offset'}, rawUtc: true);
      final cached = Messages.fromJson(post.toJson());
      for (final row in [post, websocket, refreshed, aware, cached]) {
        expect(DateTime.parse(row.messageTimestamp!), DateTime.parse('$wall$offset'));
      }
    }
    expect(Messages.fromJson({'message_timestamp': '2026-01-05T11:05:00'}).messageTimestamp,
        DateTime(2026, 1, 5, 11, 5).toUtc().toIso8601String());
  });
}
