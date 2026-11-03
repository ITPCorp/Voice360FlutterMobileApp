// Group SMS/MMS helpers, ported from voice360-fe-redesign
// src/utils/groupChat.js. A thread is a group when it has more than one
// participant besides our own number. 1:1 threads keep the old single-peer
// behaviour everywhere: with one peer every helper here returns what the old
// `participants.firstWhere((p) => p.isSelf != true)` code did.
//
// Pure Dart on purpose (no Flutter, no Hive) so it can be unit tested.

import 'dart:convert';

/// One person in a thread, flattened from either participant model
/// (threads list or thread messages) plus any name we resolved locally.
class ChatMember {
  final String number;
  final bool isSelf;
  final String? firstname;
  final String? lastname;

  /// contact.dnd_sms: this person opted out of texts.
  final bool dndSms;

  const ChatMember({
    required this.number,
    this.isSelf = false,
    this.firstname,
    this.lastname,
    this.dndSms = false,
  });

  String? get fullName {
    final full = '${firstname ?? ''} ${lastname ?? ''}'.trim();
    return full.isEmpty ? null : full;
  }
}

/// Digits only, US leading 1 dropped, so "+1 (305) 555-1234" and
/// "3055551234" compare equal.
String normalizeNumber(String? number) {
  if (number == null) return '';
  final digits = number.replaceAll(RegExp(r'\D'), '');
  if (digits.length == 11 && digits.startsWith('1')) return digits.substring(1);
  return digits;
}

bool sameNumber(String? a, String? b) {
  final na = normalizeNumber(a);
  return na.isNotEmpty && na == normalizeNumber(b);
}

/// "+1 (305) 306-2185" for US/Canada numbers, the input unchanged otherwise.
/// Same output as the web's formatPhoneNumber for NANP numbers.
String formatPhoneNumber(String? number) {
  if (number == null || number.isEmpty) return '';
  final digits = number.replaceAll(RegExp(r'\D'), '');
  String? national;
  if (digits.length == 10) national = digits;
  if (digits.length == 11 && digits.startsWith('1')) {
    national = digits.substring(1);
  }
  if (national == null) return number;
  return '+1 (${national.substring(0, 3)}) ${national.substring(3, 6)}-'
      '${national.substring(6)}';
}

/// Everyone who isn't us, de-duplicated by number, in thread order.
List<ChatMember> otherMembers(Iterable<ChatMember> members) {
  final seen = <String>{};
  final out = <ChatMember>[];
  for (final m in members) {
    if (m.isSelf || m.number.isEmpty) continue;
    final key = normalizeNumber(m.number);
    if (key.isEmpty || !seen.add(key)) continue;
    out.add(m);
  }
  return out;
}

bool isGroupThread(Iterable<ChatMember> members) =>
    otherMembers(members).length > 1;

/// Contact name, else the formatted number.
String memberName(ChatMember m) => m.fullName ?? formatPhoneNumber(m.number);

/// Short label for a group: first names (or numbers), "+N" past three.
String groupDisplayName(Iterable<ChatMember> members, {int maxShown = 3}) {
  final names = otherMembers(members).map((m) {
    final first = m.firstname?.trim();
    return (first != null && first.isNotEmpty) ? first : memberName(m);
  }).toList();
  if (names.length <= maxShown) return names.join(', ');
  return '${names.take(maxShown).join(', ')} +${names.length - maxShown}';
}

/// Every other member's full name, comma separated.
String groupFullNames(Iterable<ChatMember> members) =>
    otherMembers(members).map(memberName).join(', ');

/// "4 people", counting us. Matches the web header's "N people: ...".
String groupPeopleLabel(Iterable<ChatMember> members) =>
    '${otherMembers(members).length + 1} people';

/// Name of whoever sent an inbound group message.
String senderName(Iterable<ChatMember> members, String? senderNumber) {
  if (senderNumber == null || senderNumber.isEmpty) return '';
  for (final m in members) {
    if (!m.isSelf && sameNumber(m.number, senderNumber)) return memberName(m);
  }
  return formatPhoneNumber(senderNumber);
}

// ---------------------------------------------------------------------------
// Sending
// ---------------------------------------------------------------------------

/// Bandwidth rejects group messages above 10 participants (error 4435), and
/// our own number counts toward that. voice-api enforces the same cap.
const int kMaxGroupParticipants = 10;
const int kMaxGroupRecipients = kMaxGroupParticipants - 1;

const String kGroupLimitMessage =
    'Group texts can have up to $kMaxGroupParticipants people, including your '
    'number. Remove someone before adding another.';

/// Numbers a reply goes to: every other member. For a 1:1 this is the peer.
List<String> replyNumbers(Iterable<ChatMember> members) =>
    otherMembers(members).map((m) => m.number).toList();

/// Members who opted out of texts (contact.dnd_sms).
List<ChatMember> optedOutMembers(Iterable<ChatMember> members) =>
    otherMembers(members).where((m) => m.dndSms).toList();

/// "Ana", "Ana and Luis", "Ana, Luis and Marta".
String joinNames(Iterable<String> names) {
  final list = names.where((n) => n.isNotEmpty).toList();
  if (list.isEmpty) return '';
  if (list.length == 1) return list.first;
  return '${list.sublist(0, list.length - 1).join(', ')} and ${list.last}';
}

/// Why a group send is refused before it goes out, or null when it may go.
/// Same wording as the web's MessageInput opted-out banner.
String? groupSendBlockReason(Iterable<ChatMember> members) {
  final others = otherMembers(members);
  if (others.length > kMaxGroupRecipients) return kGroupLimitMessage;
  if (others.length < 2) return null;
  final opted = optedOutMembers(others);
  if (opted.isEmpty) return null;
  final label = joinNames(opted.map(memberName));
  final verb = opted.length == 1 ? 'has' : 'have';
  final who = opted.length == 1 ? 'that person' : 'those people';
  return '$label $verb opted out of SMS. A group text goes to everyone in it, '
      'so you cannot send to this group. Start a new conversation without '
      '$who.';
}

/// The `to_numbers_list` form field: `{"list": ["+1...", "+1..."]}`, one
/// entry per recipient. The old code joined the numbers into one string.
String toNumbersListJson(List<String> numbers) =>
    jsonEncode({'list': numbers});

/// Readable reason out of a failed send's response body. voice-api answers
/// {message, error: {code, error_message}}; the generic "An error has
/// occurred." message is skipped in favour of error_message.
String sendErrorMessage(Object? body) {
  if (body is! Map) return '';
  final err = body['error'];
  if (err is Map && err['error_message'] != null) {
    return err['error_message'].toString();
  }
  final msg = body['message'];
  if (msg != null && msg != 'An error has occurred.') return msg.toString();
  if (err is String && err.isNotEmpty) return err;
  return '';
}

/// voice-api's group cap: SMS-03 from the portal send, too_many_recipients
/// from v3.
bool isTooManyRecipientsError(Object? body) {
  if (body is! Map) return false;
  final err = body['error'];
  return (err is Map && err['code'] == 'SMS-03') ||
      err == 'too_many_recipients';
}

// ---------------------------------------------------------------------------
// Delivery receipts
// ---------------------------------------------------------------------------

/// Drops repeats of an SMS socket event we already handled. Bandwidth sends a
/// group message's delivery receipt once per recipient, all for the same
/// message, so without this one send updates (or inserts) its bubble N times.
/// Keyed by event type + message id, like the web's seenSmsEventsRef.
class SmsEventDeduper {
  final Duration ttl;
  final Map<String, DateTime> _seen = {};

  SmsEventDeduper({this.ttl = const Duration(minutes: 5)});

  /// True when an event with any of [ids] was already seen for [type].
  /// Records the ids either way.
  bool isRepeat(String type, Iterable<Object?> ids, {DateTime? now}) {
    final at = now ?? DateTime.now();
    _seen.removeWhere((_, t) => at.difference(t) > ttl);
    final keys = ids
        .where((id) => id != null && id.toString().isNotEmpty)
        .map((id) => '$type:$id')
        .toList();
    if (keys.isEmpty) return false;
    final repeat = keys.any(_seen.containsKey);
    for (final k in keys) {
      _seen[k] = at;
    }
    return repeat;
  }
}

/// Statuses a late POST response must not walk back.
const Set<String> kFinalStatuses = {'delivered', 'failed'};

/// Where a just-sent message goes in a newest-first list: the index of the
/// bubble it already has (a delivery receipt beat the POST response), or -1
/// to insert it at the top. Matches by message pk only.
int indexOfMessagePk<T>(List<T> list, int? pk, int? Function(T) pkOf) {
  if (pk == null) return -1;
  return list.indexWhere((m) => pkOf(m) == pk);
}

// ---------------------------------------------------------------------------
// Websocket routing
// ---------------------------------------------------------------------------

/// Whether an SMS socket event belongs to the open thread.
///
/// - [ownerNumber] is the Voice360 number this copy of the event is for
///   (metadata.owner_number, else the old from/to fallback). A group can
///   hold two of our numbers; each gets its own copy, so match only ours.
/// - [eventThreadId] (metadata.thread_id) decides when both sides have one.
///   It is keyed by the full participant set, so a 1:1 with Ana no longer
///   catches a group text Ana sent.
/// - Otherwise the event's participant set (sender included) must equal the
///   thread's: [threadOthers] plus us.
/// - Old payloads with neither fall back to the single peer, 1:1 only.
bool smsEventBelongsToThread({
  required String myNumber,
  required String? ownerNumber,
  required String? eventThreadId,
  required String? threadId,
  required List<String> eventParticipants,
  required String? legacyPeer,
  required List<String> threadOthers,
}) {
  if (myNumber.isNotEmpty &&
      (ownerNumber ?? '').isNotEmpty &&
      !sameNumber(ownerNumber, myNumber)) {
    return false;
  }
  if ((eventThreadId ?? '').isNotEmpty && (threadId ?? '').isNotEmpty) {
    return eventThreadId == threadId;
  }
  final wanted = threadOthers.map(normalizeNumber).where((n) => n.isNotEmpty);
  final wantedSet = wanted.toSet();
  if (eventParticipants.isNotEmpty && wantedSet.isNotEmpty) {
    final me = normalizeNumber(myNumber.isNotEmpty ? myNumber : ownerNumber);
    final got = eventParticipants
        .map(normalizeNumber)
        .where((n) => n.isNotEmpty && n != me)
        .toSet();
    return got.length == wantedSet.length && got.containsAll(wantedSet);
  }
  if (wantedSet.length != 1) return false;
  return sameNumber(legacyPeer, threadOthers.first);
}

// ---------------------------------------------------------------------------
// Compose
// ---------------------------------------------------------------------------

/// Why [candidate] can't join the recipients of a new message, or null.
/// Mirrors the web ComposeModal: no duplicates, at most
/// [kMaxGroupRecipients] people besides us.
String? recipientAddError(List<ChatMember> picked, ChatMember candidate) {
  if (picked.any((m) => sameNumber(m.number, candidate.number))) {
    return '${memberName(candidate)} is already in this conversation';
  }
  if (picked.length >= kMaxGroupRecipients) return kGroupLimitMessage;
  return null;
}
