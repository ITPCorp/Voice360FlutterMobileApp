import 'dart:convert';

enum NotificationScreen { thread, messages, voicemail, recent }

class NotificationDestination {
  const NotificationDestination(this.screen,
      {this.id,
      this.number,
      this.peer,
      this.caller,
      this.time,
      this.recordPk = false});
  final NotificationScreen screen;
  final String? id;
  final String? number;
  final String? peer;
  final String? caller;
  final int? time;
  final bool recordPk;

  static NotificationDestination? parse(Map<Object?, Object?> data) {
    final metadata = data['metadata'];
    Map<Object?, Object?> nested = {};
    if (metadata is Map) {
      nested = metadata.cast<Object?, Object?>();
    } else if (metadata is String) {
      try {
        final decoded = jsonDecode(metadata);
        if (decoded is Map) nested = decoded.cast<Object?, Object?>();
      } on FormatException {
        // Legacy CRM serializes a Python dictionary. Read individual scalar
        // fields so an apostrophe in unrelated text cannot corrupt the ID.
        final fields =
            RegExp(r"""'([a-z_]+)'\s*:\s*(?:'([^']*)'|"([^"]*)"|(\d+))""");
        for (final match in fields.allMatches(metadata)) {
          nested[match[1]] = match[2] ?? match[3] ?? match[4];
        }
      }
    }
    String? field(List<String> keys) {
      for (final key in keys) {
        final value = (data[key] ?? nested[key])?.toString().trim();
        if (value != null &&
            value.isNotEmpty &&
            value != 'null' &&
            value != 'None') {
          return value;
        }
      }
      return null;
    }

    final type = field(['type', 'item_type', 'event_type', 'notification_type'])
        ?.toLowerCase();
    if (type == 'voice360_call') return null;
    if (type == 'missed_call') {
      return NotificationDestination(NotificationScreen.recent,
          caller: field(['caller_name', 'from_number']),
          number: field(['from_number']),
          time: int.tryParse(field(['posted_at']) ?? ''));
    }
    final record = field([
      'voicemail_message_id',
      'voice_message_id',
      'voicemail_message_pk',
      'voicemail_id'
    ]);
    final explicitId = field(['voicemail_msg_id']);
    final isVoicemail = type == 'voicemail' ||
        type == 'new_voicemail' ||
        type == 'voicemail.received';
    if (isVoicemail || explicitId != null || record != null) {
      final messageId = explicitId ?? field(['msg_id']);
      return NotificationDestination(NotificationScreen.voicemail,
          id: messageId ?? record, recordPk: messageId == null);
    }
    final thread = field([
      'message_thread_id',
      'message_thread_pk',
      'thread_id',
      'conversation_id'
    ]);
    if (thread != null) {
      return NotificationDestination(NotificationScreen.thread,
          id: thread,
          number: field(['to_phone_number', 'to_number']),
          peer: field(['from_number']));
    }
    if (type == 'sms' || type == 'message' || type == 'mms') {
      return const NotificationDestination(NotificationScreen.messages);
    }
    return null;
  }
}
