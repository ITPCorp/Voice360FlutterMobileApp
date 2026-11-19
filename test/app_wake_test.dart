// App-wake pure logic: push parsing and matching the INVITE to the woken call.
import 'package:flutter_test/flutter_test.dart';
import 'package:itp_voice/services/app_wake/wake_call.dart';

WakeCall _call(String id, {String caller = '+13055550100', int? at}) => WakeCall(WakePush(
      action: 'ring',
      callId: id,
      uuid: 'uuid-$id',
      callerNumber: caller,
      receivedAtMs: at ?? DateTime.now().millisecondsSinceEpoch,
    ));

String? Function(String) _headers(Map<String, String> h) =>
    (name) => h[name];

void main() {
  group('WakePush.fromMap', () {
    test('ring with the contract keys', () {
      final p = WakePush.fromMap({
        'type': 'voice360_call',
        'action': 'ring',
        'call_id': 'ast01.dev.itpvoice.net-1763600000.42',
        'account_id': '61',
        'user_id': '206',
        'caller_id_number': '+19546109893',
        'caller_id_name': 'AW test',
        'dnis': '',
        'sent_at_ms': '1763600000123',
        'uuid': 'B9C6F0B2-0000-3000-8000-000000000000',
        'received_at_ms': '1763600000400',
      })!;
      expect(p.isRing, isTrue);
      expect(p.callId, 'ast01.dev.itpvoice.net-1763600000.42');
      expect(p.sentAtMs, 1763600000123);
      expect(p.receivedAtMs, 1763600000400);
      expect(p.uuid, startsWith('B9C6'));
    });

    test('cancel', () {
      expect(WakePush.fromMap({'type': 'voice360_call', 'action': 'cancel', 'call_id': 'x'})!.isCancel,
          isTrue);
    });

    test('other pushes and broken ones are null', () {
      expect(WakePush.fromMap({'type': 'sms', 'action': 'ring', 'call_id': 'x'}), isNull);
      expect(WakePush.fromMap({'type': 'voice360_call', 'action': 'ring'}), isNull);
      expect(WakePush.fromMap({'type': 'voice360_call', 'action': 'hold', 'call_id': 'x'}), isNull);
      expect(WakePush.fromMap(null), isNull);
    });

    test('no uuid from native falls back to the call id', () {
      expect(WakePush.fromMap({'action': 'ring', 'call_id': 'c1'})!.uuid, 'c1');
    });
  });

  group('InviteMatcher', () {
    test('X-Voice360-Call-ID wins', () {
      final a = _call('A'), b = _call('B');
      final m = InviteMatcher.match(
          _headers({'X-Voice360-Call-ID': 'B', 'X-UniqueID': 'A'}), '3055550100', [a, b]);
      expect(m!.$1, same(b));
      expect(m.$2, 'X-Voice360-Call-ID');
    });

    test('a call id header naming another call means not ours', () {
      final a = _call('A');
      expect(InviteMatcher.match(_headers({'X-Voice360-Call-ID': 'Z'}), null, [a]), isNull);
    });

    test('X-OriginalUniqueID / X-UniqueID equal to the linkedid (direct inbound)', () {
      final a = _call('ast01-1.5'), b = _call('ast01-1.9');
      final m = InviteMatcher.match(
          _headers({'X-UniqueID': 'ast01-1.9', 'X-OriginalUniqueID': 'ast01-1.9'}), null, [a, b]);
      expect(m!.$1, same(b));
      expect(m.$2, 'X-OriginalUniqueID');
    });

    test('no id match: the single waiting call, if the caller number agrees', () {
      final a = _call('A', caller: '+19546109893');
      final m = InviteMatcher.match(_headers({'X-UniqueID': 'other'}), '9546109893', [a]);
      expect(m!.$2, 'single-pending');
      expect(InviteMatcher.match(_headers({}), '3055551234', [a]), isNull);
    });

    test('no id match and two waiting calls: no guess', () {
      expect(InviteMatcher.match(_headers({}), null, [_call('A'), _call('B')]), isNull);
    });

    test('a call that already has its INVITE is not matched again', () {
      final a = _call('A')..inviteId = 'sip-1';
      expect(InviteMatcher.match(_headers({'X-UniqueID': 'A'}), null, [a]), isNull);
    });

    test('stale single pending call is not taken by the fallback', () {
      final old = _call('A', at: 1000);
      expect(InviteMatcher.match(_headers({}), null, [old], nowMs: 1000 + 120000), isNull);
    });

    test('sameNumber', () {
      expect(InviteMatcher.sameNumber('+13055550100', '3055550100'), isTrue);
      expect(InviteMatcher.sameNumber('13055550100', '+1 (305) 555-0100'), isTrue);
      expect(InviteMatcher.sameNumber('', '3055550100'), isTrue);
      expect(InviteMatcher.sameNumber('101', '102'), isFalse);
      expect(InviteMatcher.sameNumber('+13055550100', '3055550199'), isFalse);
    });
  });

  group('WakeTimings', () {
    test('offsets from the push', () {
      final c = _call('A', at: 10000);
      c.t.serverSent = 9700;
      c.t.registered = 11500;
      c.t.invite = 12100;
      final j = c.t.toJson('A');
      expect(j['push_transit_ms'], 300);
      expect(j['register_ms'], 1500);
      expect(j['invite_ms'], 2100);
      expect(c.t.summary(), contains('reg200 1500ms'));
    });
  });
}
