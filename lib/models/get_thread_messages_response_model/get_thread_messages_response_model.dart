class GetThreadMessagesResponseModel {
  Result? result;
  bool? errors;
  dynamic error;
  String? message;
  dynamic pageSize;
  dynamic nextStartKey;
  dynamic startKey;

  GetThreadMessagesResponseModel(
      {this.result, this.errors, this.error, this.message, this.pageSize, this.nextStartKey, this.startKey});

  GetThreadMessagesResponseModel.fromJson(Map<String, dynamic> json) {
    result = json['result'] != null ? new Result.fromJson(json['result']) : null;
    errors = json['errors'];
    error = json['error'];
    message = json['message'];
    pageSize = json['page_size'];
    nextStartKey = json['next_start_key'];
    startKey = json['start_key'];
  }

  Map<String, dynamic> toJson() {
    final Map<String, dynamic> data = new Map<String, dynamic>();
    if (this.result != null) {
      data['result'] = this.result!.toJson();
    }
    data['errors'] = this.errors;
    data['error'] = this.error;
    data['message'] = this.message;
    data['page_size'] = this.pageSize;
    data['next_start_key'] = this.nextStartKey;
    data['start_key'] = this.startKey;
    return data;
  }
}

class Result {
  List<Messages>? messages;
  List<Participants>? participants;

  Result({this.messages, this.participants});

  Result.fromJson(Map<String, dynamic> json) {
    if (json['messages'] != null) {
      messages = <Messages>[];
      json['messages'].forEach((v) {
        messages!.add(new Messages.fromJson(v));
      });
    }
    if (json['participants'] != null) {
      participants = <Participants>[];
      json['participants'].forEach((v) {
        participants!.add(new Participants.fromJson(v));
      });
    }
  }

  Map<String, dynamic> toJson() {
    final Map<String, dynamic> data = new Map<String, dynamic>();
    if (this.messages != null) {
      data['messages'] = this.messages!.map((v) => v.toJson()).toList();
    }
    if (this.participants != null) {
      data['participants'] = this.participants!.map((v) => v.toJson()).toList();
    }
    return data;
  }
}

class Messages {
  String? messageStatus;
  int? pk;
  String? messageBody;
  String? messageProviderId;
  dynamic messageMmsMedia;
  CallBackResponse? callBackResponse;
  String? messageTimestamp;
  String? messageParticipantId;
  String? messageParticipant;
  bool? isDelivered;

  // ---- Call-entry fields (optional; populated when itemType == 'call'). ----
  /// 'sms' | 'call' | 'voicemail'. `null` is treated as 'sms' for legacy rows.
  String? itemType;

  /// 'inbound' | 'outbound' | 'forwarded'.
  String? callDirection;

  /// 'answered' | 'missed' | 'busy' | 'failed' | ...
  String? callStatus;

  /// Seconds. Backed by `call_duration` (or `billsec` as a fallback).
  int? callDuration;

  /// Server-side filename for the recording. When present, we build the
  /// playback URL via `cdr/<cdrPk>/download-recording/raw?token=...`.
  String? callRecordingFilename;

  /// Raw AWS-Transcribe-Call-Analytics JSON string. Parsed lazily.
  String? callTranscription;

  /// CDR primary key — needed to build the recording download URL.
  int? cdrPk;

  /// True for AI-handled calls (label/icon swap).
  bool aiCall = false;

  /// Voicemail-entry fields (lightweight; voicemail tab still owns playback).
  String? voicemailLink;
  int? voicemailDuration;
  String? voicemailTranscription;

  Messages({
    this.messageStatus,
    this.pk,
    this.messageBody,
    this.messageProviderId,
    this.messageMmsMedia,
    this.callBackResponse,
    this.messageTimestamp,
    this.messageParticipantId,
    this.messageParticipant,
    this.isDelivered = true,
    this.itemType,
    this.callDirection,
    this.callStatus,
    this.callDuration,
    this.callRecordingFilename,
    this.callTranscription,
    this.cdrPk,
    this.aiCall = false,
    this.voicemailLink,
    this.voicemailDuration,
    this.voicemailTranscription,
  });

  bool get isCall => itemType == 'call';
  bool get isVoicemail => itemType == 'voicemail';
  bool get isSms => !isCall && !isVoicemail;
  bool get hasRecording =>
      callRecordingFilename != null && callRecordingFilename!.isNotEmpty;
  bool get hasTranscript =>
      (callTranscription != null && callTranscription!.trim().isNotEmpty);

  Messages.fromJson(Map<String, dynamic> json) {
    messageStatus = json['message_status'];
    pk = json['pk'];
    messageBody = json['message_body'];
    messageProviderId = json['message_provider_id'];
    messageMmsMedia = json['message_mms_media'];
    callBackResponse = json['call_back_response'] != null
        ? new CallBackResponse.fromJson(json['call_back_response'])
        : null;
    messageTimestamp = json['message_timestamp'];
    messageParticipantId = json['message_participant_id'];
    messageParticipant = json['message_participant'];
    isDelivered = true;

    // Call/voicemail extras — same row can carry these fields when the API
    // returns a mixed timeline. Tolerate either flat or nested CDR shape.
    itemType = (json['item_type'] as String?)?.toLowerCase();
    callDirection = (json['call_direction'] as String?)?.toLowerCase();
    callStatus = (json['call_status'] as String?)?.toLowerCase();
    callDuration = (json['call_duration'] as num?)?.toInt() ??
        (json['billsec'] as num?)?.toInt();
    callRecordingFilename = json['call_recording_filename'] as String?;
    callTranscription = _readTranscription(json);
    cdrPk = (json['cdr_pk'] as num?)?.toInt() ??
        (json['call_pk'] as num?)?.toInt() ??
        (json['cdr'] is Map ? (json['cdr']['pk'] as num?)?.toInt() : null);
    aiCall = json['ai_call'] == true || json['was_ai'] == true;

    // Voicemail fields (when item_type == 'voicemail').
    voicemailLink = json['voicemail_link'] as String?;
    voicemailDuration = (json['voicemail_duration'] as num?)?.toInt();
    voicemailTranscription = json['voicemail_transcription'] as String?;

    // Nested CDR fallback (voice360-fe shape: `cdr.call_recording_filename`).
    if (json['cdr'] is Map) {
      final cdr = (json['cdr'] as Map).cast<String, dynamic>();
      callRecordingFilename ??= cdr['call_recording_filename'] as String?;
      callDuration ??= (cdr['duration'] as num?)?.toInt() ??
          (cdr['billsec'] as num?)?.toInt();
      cdrPk ??= (cdr['pk'] as num?)?.toInt();
      callTranscription ??= _readTranscription(cdr);
    }

    // If the row clearly came from a call response but item_type was omitted,
    // promote it client-side.
    if (itemType == null &&
        (callRecordingFilename != null ||
            callDirection != null ||
            callStatus != null ||
            cdrPk != null)) {
      itemType = 'call';
    }
  }

  /// The server may serialise the transcription either as a raw JSON string
  /// or as a nested `{transcription: "..."}` object. Normalise to a string.
  static String? _readTranscription(Map<String, dynamic> source) {
    final raw = source['call_transcription'];
    if (raw == null) return null;
    if (raw is String) return raw.isEmpty ? null : raw;
    if (raw is Map) {
      final inner = raw['transcription'] ?? raw['formatedTranscription'];
      if (inner is String && inner.isNotEmpty) return inner;
    }
    return null;
  }

  Messages.fromPayload(Map<String, dynamic> json) {
    messageStatus = json['message_status'];
    pk = json['message_thread_pk'];
    messageBody = json['message'];
    messageProviderId = json['message_provider_id'];
    messageMmsMedia = json['media_id'];
    messageTimestamp = json['message_timestamp'];
    messageParticipant = json['from_number'];
    isDelivered = true;
    aiCall = false;
  }

  Map<String, dynamic> toJson() {
    final Map<String, dynamic> data = <String, dynamic>{};
    data['message_status'] = messageStatus;
    data['pk'] = pk;
    data['message_body'] = messageBody;
    data['message_provider_id'] = messageProviderId;
    data['message_mms_media'] = messageMmsMedia;
    if (callBackResponse != null) {
      data['call_back_response'] = callBackResponse!.toJson();
    }
    data['message_timestamp'] = messageTimestamp;
    data['message_participant_id'] = messageParticipantId;
    data['message_participant'] = messageParticipant;
    // Persist call/voicemail extras so cached chats restore correctly.
    if (itemType != null) data['item_type'] = itemType;
    if (callDirection != null) data['call_direction'] = callDirection;
    if (callStatus != null) data['call_status'] = callStatus;
    if (callDuration != null) data['call_duration'] = callDuration;
    if (callRecordingFilename != null) {
      data['call_recording_filename'] = callRecordingFilename;
    }
    if (callTranscription != null) data['call_transcription'] = callTranscription;
    if (cdrPk != null) data['cdr_pk'] = cdrPk;
    if (aiCall) data['ai_call'] = true;
    if (voicemailLink != null) data['voicemail_link'] = voicemailLink;
    if (voicemailDuration != null) data['voicemail_duration'] = voicemailDuration;
    if (voicemailTranscription != null) {
      data['voicemail_transcription'] = voicemailTranscription;
    }
    return data;
  }
}

class CallBackResponse {
  CallBackResponse();

  CallBackResponse.fromJson(Map<String, dynamic> json) {}

  Map<String, dynamic> toJson() {
    final Map<String, dynamic> data = new Map<String, dynamic>();
    return data;
  }
}

class Participants {
  String? messageThreadId;
  int? pk;
  String? number;
  bool? isSelf;

  /// Server-side join — see [ParticipantContact].
  ParticipantContact? contact;

  Participants({
    this.messageThreadId,
    this.pk,
    this.number,
    this.isSelf,
    this.contact,
  });

  String? get contactName {
    final c = contact;
    if (c == null) return null;
    final full = ('${c.firstname ?? ''} ${c.lastname ?? ''}').trim();
    return full.isEmpty ? null : full;
  }

  Participants.fromJson(Map<String, dynamic> json) {
    messageThreadId = json['message_thread_id'];
    pk = json['pk'];
    number = json['number'];
    isSelf = json['is_self'];
    final raw = json['contact'];
    if (raw is Map) {
      contact = ParticipantContact.fromJson(raw.cast<String, dynamic>());
    }
  }

  Map<String, dynamic> toJson() {
    final Map<String, dynamic> data = <String, dynamic>{};
    data['message_thread_id'] = messageThreadId;
    data['pk'] = pk;
    data['number'] = number;
    data['is_self'] = isSelf;
    if (contact != null) data['contact'] = contact!.toJson();
    return data;
  }
}

class ParticipantContact {
  int? pk;
  String? firstname;
  String? lastname;
  String? phone;
  String? email;

  ParticipantContact(
      {this.pk, this.firstname, this.lastname, this.phone, this.email});

  ParticipantContact.fromJson(Map<String, dynamic> json)
      : pk = (json['pk'] as num?)?.toInt(),
        firstname = json['firstname'] as String?,
        lastname = json['lastname'] as String?,
        phone = json['phone'] as String?,
        email = json['email'] as String?;

  Map<String, dynamic> toJson() => {
        'pk': pk,
        'firstname': firstname,
        'lastname': lastname,
        'phone': phone,
        'email': email,
      };
}
