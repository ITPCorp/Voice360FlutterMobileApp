import 'package:flutter_test/flutter_test.dart';
import 'package:itp_voice/models/get_thread_messages_response_model/get_thread_messages_response_model.dart';
import 'package:itp_voice/services/global_socket_service.dart';

SmsEventReader reader(String type, Map<String, dynamic> data) =>
    SmsEventReader(GlobalSocketEvent(
        outerType: 'notification', innerType: type, data: data));

void main() {
  test('group fields are read from metadata', () {
    final r = reader('sms.received', {
      'metadata': {
        'thread_id': 489286,
        'owner_number': '+13053301236',
        'from_number': '+13055550101',
        'to_numbers_list': ['+13053062185', '+13053301236'],
        'participants': ['+13053062185', '+13053301236', '+13055550101'],
        'sms_body': 'TEST group',
        'provider_message_id': 'bw-1',
      }
    });
    expect(r.threadId, '489286');
    expect(r.ownerNumber, '+13053301236');
    expect(r.fromNumber, '+13055550101');
    expect(r.participantNumbers.length, 3);
    expect(r.body, 'TEST group');
    expect(r.providerId, 'bw-1');
  });

  test('flat fields and participant objects work too', () {
    final r = reader('sms.sent', {
      'thread_id': '77',
      'from_number': '+13053062185',
      'to_number': ['+13055550101', '+13055550102'],
      'message_content_id': 4242,
      'participants': [
        {'number': '+13053062185', 'is_self': true},
        {'number': '+13055550101'},
      ],
    });
    expect(r.threadId, '77');
    expect(r.toNumbers, ['+13055550101', '+13055550102']);
    expect(r.messagePk, 4242);
    expect(r.participantNumbers, ['+13053062185', '+13055550101']);
    // No owner_number on sms.sent: we are the sender.
    expect(r.ownerNumber, '+13053062185');
  });

  test('no owner_number on an inbound group: our number among the recipients',
      () {
    final r = reader('sms.received', {
      'from_number': '+13055550101',
      'to_numbers_list': ['+15612210454', '+13053062185'],
    });
    expect(r.ownerNumber, '+15612210454'); // old to_numbers_list[0] guess
    expect(r.ownerNumberFor('+13053062185'), '+13053062185');
  });

  test('legacy payload builds an inbound bubble without throwing', () {
    final r = reader('sms.received', {
      'from_number': '+13055550101',
      'body': 'TEST',
      'message_content_id': '99',
      'thread': {'pk': 12},
    });
    final m = Messages.fromPayload(r.toLegacyPayload());
    expect(m.pk, 99);
    expect(m.messageParticipant, '+13055550101');
    expect(m.messageBody, 'TEST');
  });
}
