// App-wake: the pure parts (no plugins), so they can be unit tested.
//
// Contract: /workspace/.scratch/app-wake/CONTRACT.md (workbench). The dialplan
// adds a Local "app-wake" leg next to the user's devices when the app_phone is
// not registered. That leg POSTs a push (type=voice360_call, action=ring), waits
// for the app to REGISTER, then INVITEs it through the Kamailio holding the
// registration. When the leg ends without the app answering it sends
// action=cancel. Payload keys (all strings): type, action, call_id, account_id,
// user_id, caller_id_number, caller_id_name, dnis, sent_at_ms.

/// One push as the native side hands it to Dart.
class WakePush {
  final String action; // ring | cancel
  final String callId; // Asterisk linkedid, stable across legs
  /// Id of the native call UI: the CallKit UUID on iOS, the
  /// flutter_callkit_incoming id on Android. Derived natively from [callId].
  final String uuid;
  final String callerNumber;
  final String callerName;
  final String dnis;
  final String? reason;

  /// Server clock (asterisk-api) when the push left, ms since epoch.
  final int? sentAtMs;

  /// Device clock when the native push handler ran, ms since epoch.
  final int receivedAtMs;

  /// What native already did with it ("shown", "ended", "ignored", ...).
  final String? nativeResult;

  const WakePush({
    required this.action,
    required this.callId,
    required this.uuid,
    this.callerNumber = '',
    this.callerName = '',
    this.dnis = '',
    this.reason,
    this.sentAtMs,
    required this.receivedAtMs,
    this.nativeResult,
  });

  bool get isRing => action == 'ring';
  bool get isCancel => action == 'cancel';

  /// Null when [m] is not a usable voice360_call push.
  static WakePush? fromMap(Map<dynamic, dynamic>? m) {
    if (m == null) return null;
    String s(String k) => (m[k] ?? '').toString();
    if (s('type').isNotEmpty && s('type') != 'voice360_call') return null;
    final action = s('action');
    final callId = s('call_id');
    if ((action != 'ring' && action != 'cancel') || callId.isEmpty) return null;
    return WakePush(
      action: action,
      callId: callId,
      uuid: s('uuid').isEmpty ? callId : s('uuid'),
      callerNumber: s('caller_id_number'),
      callerName: s('caller_id_name'),
      dnis: s('dnis'),
      reason: s('reason').isEmpty ? null : s('reason'),
      sentAtMs: int.tryParse(s('sent_at_ms')),
      receivedAtMs:
          int.tryParse(s('received_at_ms')) ?? DateTime.now().millisecondsSinceEpoch,
      nativeResult: s('native_result').isEmpty ? null : s('native_result'),
    );
  }
}

/// Wall-clock marks for one woken call, ms since epoch (device clock except
/// [serverSent]). Caesar wants push -> REGISTER 200 -> INVITE on real phones,
/// to judge whether APP_WAKE_WAIT_ALONE=6 s is enough.
class WakeTimings {
  int? serverSent; // sent_at_ms from the push (server clock)
  int pushReceived; // native push handler
  int? dartSeen; // Dart got the event (engine start on a cold wake)
  int? uaStart; // SIP UA start() called
  int? wsConnected; // WSS up
  int? registered; // REGISTER 200
  int? invite; // matching INVITE arrived
  int? answerTap; // user tapped Answer on the native UI
  int? answered; // 200 OK sent / session accepted
  int? mediaReady; // confirmed SIP call with inbound audio on Android
  int? ended;
  String? outcome;
  String? matchedBy;
  bool alreadyRegistered = false;
  bool coldStart = false;

  WakeTimings(this.pushReceived);

  int? since(int? t) => t == null ? null : t - pushReceived;

  Map<String, dynamic> toJson(String callId) => {
        'call_id': callId,
        'at': DateTime.fromMillisecondsSinceEpoch(pushReceived).toIso8601String(),
        'push_transit_ms': serverSent == null ? null : pushReceived - serverSent!,
        'dart_ms': since(dartSeen),
        'ua_start_ms': since(uaStart),
        'ws_ms': since(wsConnected),
        'register_ms': since(registered),
        'invite_ms': since(invite),
        'answer_tap_ms': since(answerTap),
        'answered_ms': since(answered),
        'ended_ms': since(ended),
        'outcome': outcome,
        'matched_by': matchedBy,
        'already_registered': alreadyRegistered,
        'cold_start': coldStart,
      };

  /// One line for logs and the debug screen.
  String summary() {
    String f(int? v) => v == null ? '-' : '${v}ms';
    return 'push+${serverSent == null ? '?' : '${pushReceived - serverSent!}ms'} '
        'dart ${f(since(dartSeen))} ws ${f(since(wsConnected))} '
        'reg200 ${f(since(registered))} invite ${f(since(invite))} '
        'tap ${f(since(answerTap))} ans ${f(since(answered))} '
        '${outcome ?? ''}${matchedBy == null ? '' : ' by $matchedBy'}'
        '${coldStart ? ' cold' : ''}${alreadyRegistered ? ' prereg' : ''}';
  }
}

bool hasInboundAudio(String type, Map<dynamic, dynamic> values) {
  if (type != 'inbound-rtp' || (values['kind'] ?? values['mediaType']) != 'audio') {
    return false;
  }
  final packets = values['packetsReceived'];
  return packets is num && packets > 0;
}

enum WakeState { ringing, answering, answered, ended }

/// A call the app was woken for.
class WakeCall {
  WakePush push;
  final WakeTimings t;
  WakeState state = WakeState.ringing;

  /// sip_ua Call id of the matched INVITE, null until it arrives.
  String? inviteId;

  /// User tapped Answer (possibly before the INVITE arrived).
  bool accepted = false;

  /// User tapped Decline (possibly before the INVITE arrived): reject it 603.
  bool declined = false;

  /// A cancel push came, or the native UI was already ended.
  bool nativeEnded = false;

  WakeCall(this.push) : t = WakeTimings(push.receivedAtMs) {
    t.serverSent = push.sentAtMs;
  }

  String get callerLabel => push.callerName.trim().isNotEmpty
      ? push.callerName
      : (push.callerNumber.isEmpty ? 'Caller ID unavailable' : push.callerNumber);
  String get callId => push.callId;
  String get uuid => push.uuid;
  bool get waitingForInvite => inviteId == null && state != WakeState.ended;
}

/// Matches an incoming INVITE to the call the user was woken for.
///
/// What the dialplan puts on a device INVITE ([predialer-dial-user],
/// itpvoice-asterisk-dialplan feature/app-wake 0576680): X-Voice360Domain,
/// X-UniqueID (UNIQUEID of the channel running callflow_user), X-OriginalUniqueID,
/// X-AsteriskChannel, X-Voice360-Trace-ID, X-Voice360-Ext. The push call_id is
/// CHANNEL(linkedid) of that same channel. For a plain PSTN call they are equal,
/// so X-UniqueID / X-OriginalUniqueID match. After an IVR, queue, transfer or a
/// Local-originated call they differ, so the dialplan should also send the
/// linkedid (asked for as `X-Voice360-Call-ID: ${CHANNEL(linkedid)}`).
class InviteMatcher {
  /// Exact call id headers, first match wins. X-Voice360-Call-ID is the one
  /// asked of the dialplan; the others are accepted in case it is named so.
  static const callIdHeaders = [
    'X-Voice360-Call-ID',
    'X-Voice360-Linkedid',
    'X-LinkedID',
  ];

  /// Headers that equal the linkedid on a direct inbound call.
  static const uniqueIdHeaders = ['X-OriginalUniqueID', 'X-UniqueID'];

  /// Max age of a pending wake call that the single-pending fallback may take.
  static const fallbackWindow = Duration(seconds: 90);

  /// [header] reads one header from the INVITE (null when absent).
  /// [fromUser] is the From user part (caller number).
  /// Returns the matched call and how it matched, or null.
  static (WakeCall, String)? match(
    String? Function(String name) header,
    String? fromUser,
    Iterable<WakeCall> calls, {
    int? nowMs,
  }) {
    final pending = calls.where((c) => c.waitingForInvite).toList();
    if (pending.isEmpty) return null;
    for (final h in callIdHeaders) {
      final v = header(h)?.trim();
      if (v == null || v.isEmpty) continue;
      for (final c in pending) {
        if (c.callId == v) return (c, h);
      }
      // The dialplan named this call: it is not one of ours.
      return null;
    }
    for (final h in uniqueIdHeaders) {
      final v = header(h)?.trim();
      if (v == null || v.isEmpty) continue;
      for (final c in pending) {
        if (c.callId == v) return (c, h);
      }
    }
    // No id match. Take it only when exactly one woken call is waiting, it is
    // recent, and the caller number does not contradict it.
    final now = nowMs ?? DateTime.now().millisecondsSinceEpoch;
    final recent = pending
        .where((c) => now - c.t.pushReceived <= fallbackWindow.inMilliseconds)
        .toList();
    if (recent.length != 1) return null;
    final c = recent.single;
    if (!sameNumber(c.push.callerNumber, fromUser)) return null;
    return (c, 'single-pending');
  }

  /// True when both numbers end in the same 10 digits, or either is unknown.
  static bool sameNumber(String? a, String? b) {
    final da = _digits(a);
    final db = _digits(b);
    if (da.isEmpty || db.isEmpty) return true;
    final n = da.length < db.length ? da.length : db.length;
    final k = n < 10 ? n : 10;
    return da.substring(da.length - k) == db.substring(db.length - k);
  }

  static String _digits(String? s) => (s ?? '').replaceAll(RegExp(r'[^0-9]'), '');
}
