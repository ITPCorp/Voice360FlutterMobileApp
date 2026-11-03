// Group SMS/MMS helpers, ported from voice360-fe-redesign
// src/utils/groupChat.js. A thread is a group when it has more than one
// participant besides our own number. 1:1 threads keep the old single-peer
// behaviour everywhere: with one peer every helper here returns what the old
// `participants.firstWhere((p) => p.isSelf != true)` code did.
//
// Pure Dart on purpose (no Flutter, no Hive) so it can be unit tested.

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
