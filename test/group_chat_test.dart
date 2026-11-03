import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:itp_voice/helpers/group_chat.dart';

const me = ChatMember(number: '+13053062185', isSelf: true);
const ana = ChatMember(number: '+13055550101', firstname: 'Ana', lastname: 'Diaz');
const luis = ChatMember(number: '+13055550102', firstname: 'Luis');
const bare = ChatMember(number: '+15612210454');

void main() {
  group('numbers', () {
    test('normalizeNumber drops punctuation and the US 1', () {
      expect(normalizeNumber('+1 (305) 555-1234'), '3055551234');
      expect(normalizeNumber('3055551234'), '3055551234');
      expect(normalizeNumber('+525512345678'), '525512345678');
      expect(normalizeNumber(null), '');
    });

    test('sameNumber', () {
      expect(sameNumber('+13055551234', '305-555-1234'), isTrue);
      expect(sameNumber('+13055551234', '+13055551235'), isFalse);
      expect(sameNumber('', ''), isFalse);
    });

    test('formatPhoneNumber matches the web', () {
      expect(formatPhoneNumber('+13053062185'), '+1 (305) 306-2185');
      expect(formatPhoneNumber('3053062185'), '+1 (305) 306-2185');
      expect(formatPhoneNumber('+525512345678'), '+525512345678');
    });

    test('toE164', () {
      expect(toE164('3055551234'), '+13055551234');
      expect(toE164('13055551234'), '+13055551234');
      expect(toE164('+1 (305) 555-1234'), '+13055551234');
      expect(toE164(''), '');
    });
  });

  group('participant naming', () {
    test('1:1 is not a group', () {
      expect(isGroupThread([me, ana]), isFalse);
      // The same peer twice is still one peer.
      expect(isGroupThread([me, ana, const ChatMember(number: '3055550101')]),
          isFalse);
    });

    test('two peers is a group', () {
      expect(isGroupThread([me, ana, luis]), isTrue);
    });

    test('memberName: contact name, else formatted number', () {
      expect(memberName(ana), 'Ana Diaz');
      expect(memberName(bare), '+1 (561) 221-0454');
    });

    test('groupDisplayName uses first names and +N past three', () {
      expect(groupDisplayName([me, ana, luis, bare]),
          'Ana, Luis, +1 (561) 221-0454');
      final many = [
        me,
        ana,
        luis,
        bare,
        const ChatMember(number: '+13055550104', firstname: 'Marta'),
        const ChatMember(number: '+13055550105', firstname: 'Pedro'),
      ];
      expect(groupDisplayName(many), 'Ana, Luis, +1 (561) 221-0454 +2');
    });

    test('groupFullNames and people label count us', () {
      expect(groupFullNames([me, ana, luis]), 'Ana Diaz, Luis');
      expect(groupPeopleLabel([me, ana, luis]), '3 people');
    });

    test('senderName finds the member, else formats the number', () {
      expect(senderName([me, ana, luis], '3055550101'), 'Ana Diaz');
      expect(senderName([me, ana, luis], '+17865550000'), '+1 (786) 555-0000');
      expect(senderName([me, ana], null), '');
    });
  });

  group('reply-all', () {
    test('replyNumbers is everyone but us, deduped', () {
      expect(replyNumbers([me, ana, luis, const ChatMember(number: '3055550101')]),
          ['+13055550101', '+13055550102']);
      expect(replyNumbers([me, ana]), ['+13055550101']);
    });

    test('toNumbersListJson emits one entry per recipient', () {
      final json = toNumbersListJson(['+13055550101', '+13055550102']);
      expect(jsonDecode(json), {
        'list': ['+13055550101', '+13055550102']
      });
      // The old bug: one string holding both numbers.
      expect(json.contains('+13055550101,+13055550102'), isFalse);
    });

    test('groupSendBlockReason: opted-out member blocks a group', () {
      const opted = ChatMember(
          number: '+13055550109', firstname: 'Rosa', dndSms: true);
      expect(groupSendBlockReason([me, ana, luis]), isNull);
      expect(groupSendBlockReason([me, ana, opted]),
          startsWith('Rosa has opted out of SMS.'));
      // A 1:1 is not this function's business.
      expect(groupSendBlockReason([me, opted]), isNull);
    });

    test('joinNames', () {
      expect(joinNames(['Ana']), 'Ana');
      expect(joinNames(['Ana', 'Luis']), 'Ana and Luis');
      expect(joinNames(['Ana', 'Luis', 'Marta']), 'Ana, Luis and Marta');
    });

    test('send error helpers read voice-api bodies', () {
      final capped = {
        'message': 'An error has occurred.',
        'error': {'code': 'SMS-03', 'error_message': 'Too many recipients'}
      };
      expect(sendErrorMessage(capped), 'Too many recipients');
      expect(isTooManyRecipientsError(capped), isTrue);
      expect(isTooManyRecipientsError({'error': 'too_many_recipients'}), isTrue);
      expect(isTooManyRecipientsError({'error': 'other'}), isFalse);
      expect(sendErrorMessage(null), '');
    });
  });

  group('cap', () {
    List<ChatMember> people(int n) => [
          for (var i = 0; i < n; i++)
            ChatMember(number: '+1305555${(1000 + i).toString()}')
        ];

    test('ten people including us: nine recipients allowed', () {
      expect(kMaxGroupParticipants, 10);
      expect(kMaxGroupRecipients, 9);
      expect(recipientAddError(people(8), const ChatMember(number: '+17865550000')),
          isNull);
      expect(recipientAddError(people(9), const ChatMember(number: '+17865550000')),
          kGroupLimitMessage);
    });

    test('limit message matches the web wording', () {
      expect(kGroupLimitMessage,
          'Group texts can have up to 10 people, including your number. '
          'Remove someone before adding another.');
    });

    test('duplicates are refused', () {
      expect(recipientAddError([ana], const ChatMember(number: '305-555-0101')),
          '+1 (305) 555-0101 is already in this conversation');
    });

    test('a group over the cap cannot send', () {
      expect(groupSendBlockReason([me, ...people(10)]), kGroupLimitMessage);
      expect(groupSendBlockReason([me, ...people(9)]), isNull);
    });
  });

  group('receipt dedupe', () {
    test('per-recipient receipts of one message collapse to one', () {
      final d = SmsEventDeduper();
      final t0 = DateTime(2026, 11, 3, 12);
      expect(d.isRepeat('sms.sent', [4242, 'bw-1'], now: t0), isFalse);
      expect(d.isRepeat('sms.sent', [4242, 'bw-1'], now: t0), isTrue);
      expect(d.isRepeat('sms.sent', [4242, null], now: t0), isTrue);
      // Another message, or another event type, is not a repeat.
      expect(d.isRepeat('sms.sent', [4243, 'bw-2'], now: t0), isFalse);
      expect(d.isRepeat('sms.received', [4242], now: t0), isFalse);
    });

    test('no ids: never treated as a repeat', () {
      final d = SmsEventDeduper();
      expect(d.isRepeat('sms.sent', [null, ''], now: DateTime(2026)), isFalse);
      expect(d.isRepeat('sms.sent', [null, ''], now: DateTime(2026)), isFalse);
    });

    test('entries expire after the ttl', () {
      final d = SmsEventDeduper(ttl: const Duration(minutes: 5));
      final t0 = DateTime(2026, 11, 3, 12);
      d.isRepeat('sms.sent', [1], now: t0);
      expect(d.isRepeat('sms.sent', [1], now: t0.add(const Duration(minutes: 6))),
          isFalse);
    });

    test('indexOfMessagePk finds the bubble a receipt created', () {
      final list = [
        {'pk': 3},
        {'pk': 2}
      ];
      expect(indexOfMessagePk<Map<String, int>>(list, 2, (m) => m['pk']), 1);
      expect(indexOfMessagePk<Map<String, int>>(list, 9, (m) => m['pk']), -1);
      expect(indexOfMessagePk<Map<String, int>>(list, null, (m) => m['pk']), -1);
    });
  });

  group('socket routing', () {
    const mine = '+13053062185';

    test('thread_id decides when both sides have one', () {
      expect(
          smsEventBelongsToThread(
            myNumber: mine,
            ownerNumber: mine,
            eventThreadId: '77',
            threadId: '77',
            eventParticipants: const [],
            legacyPeer: null,
            threadOthers: const ['+13055550101'],
          ),
          isTrue);
      // Group text from Ana must not land in the 1:1 with Ana.
      expect(
          smsEventBelongsToThread(
            myNumber: mine,
            ownerNumber: mine,
            eventThreadId: '88',
            threadId: '77',
            eventParticipants: const [mine, '+13055550101', '+13055550102'],
            legacyPeer: '+13055550101',
            threadOthers: const ['+13055550101'],
          ),
          isFalse);
    });

    test('event for another of our numbers is skipped', () {
      expect(
          smsEventBelongsToThread(
            myNumber: mine,
            ownerNumber: '+13053301236',
            eventThreadId: '77',
            threadId: '77',
            eventParticipants: const [],
            legacyPeer: null,
            threadOthers: const ['+13055550101'],
          ),
          isFalse);
    });

    test('participant set match when there is no thread id', () {
      expect(
          smsEventBelongsToThread(
            myNumber: mine,
            ownerNumber: mine,
            eventThreadId: null,
            threadId: null,
            eventParticipants: const ['+13055550102', mine, '+13055550101'],
            legacyPeer: '+13055550102',
            threadOthers: const ['3055550101', '3055550102'],
          ),
          isTrue);
      expect(
          smsEventBelongsToThread(
            myNumber: mine,
            ownerNumber: mine,
            eventThreadId: null,
            threadId: null,
            eventParticipants: const [mine, '+13055550101'],
            legacyPeer: '+13055550101',
            threadOthers: const ['3055550101', '3055550102'],
          ),
          isFalse);
    });

    test('old payloads fall back to the single peer, 1:1 only', () {
      expect(
          smsEventBelongsToThread(
            myNumber: mine,
            ownerNumber: null,
            eventThreadId: null,
            threadId: '77',
            eventParticipants: const [],
            legacyPeer: '305-555-0101',
            threadOthers: const ['+13055550101'],
          ),
          isTrue);
      expect(
          smsEventBelongsToThread(
            myNumber: mine,
            ownerNumber: null,
            eventThreadId: null,
            threadId: '77',
            eventParticipants: const [],
            legacyPeer: '+13055550101',
            threadOthers: const ['+13055550101', '+13055550102'],
          ),
          isFalse);
    });
  });

  group('find-thread', () {
    test('1:1 sends encoded E.164 second_participant', () {
      expect(findThreadQuery(['3055550101']),
          'offset=0&limit=20&second_participant=%2B13055550101');
      expect(findThreadQuery(['+13055550101']),
          'offset=0&limit=20&second_participant=%2B13055550101');
    });

    test('group sends participants, comma separated and encoded', () {
      expect(
          findThreadQuery(['+13055550101', '305 555 0102']),
          'offset=0&limit=20&second_participant='
          '&participants=%2B13055550101%2C%2B13055550102');
    });

    test('threadIdFromFindThread', () {
      expect(
          threadIdFromFindThread({
            'result': [
              {'message_thread_id': 489286}
            ]
          }),
          '489286');
      expect(threadIdFromFindThread({'result': null}), isNull);
      expect(threadIdFromFindThread('oops'), isNull);
    });
  });
}
