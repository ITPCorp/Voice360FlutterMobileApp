class GetMessageThreadsResponseModel {
  Result? result;
  bool? errors;
  Null? error;
  String? message;
  Null? pageSize;
  Null? nextStartKey;
  Null? startKey;

  GetMessageThreadsResponseModel(
      {this.result, this.errors, this.error, this.message, this.pageSize, this.nextStartKey, this.startKey});

  GetMessageThreadsResponseModel.fromJson(Map<String, dynamic> json) {
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
  List<MessageThreads>? messageThreads;
  int? totalPages;
  int? page;

  Result({this.messageThreads, this.totalPages, this.page});

  Result.fromJson(Map<String, dynamic> json) {
    if (json['message_threads'] != null) {
      messageThreads = <MessageThreads>[];
      json['message_threads'].forEach((v) {
        messageThreads!.add(new MessageThreads.fromJson(v));
      });
    }
    totalPages = json['total_pages'];
    page = json['page'];
  }

  Map<String, dynamic> toJson() {
    final Map<String, dynamic> data = new Map<String, dynamic>();
    if (this.messageThreads != null) {
      data['message_threads'] = this.messageThreads!.map((v) => v.toJson()).toList();
    }
    data['total_pages'] = this.totalPages;
    data['page'] = this.page;
    return data;
  }
}

class MessageThreads {
  bool? threadRead;
  String? lastMessage;
  String? lastUpdated;
  int? numberOfParticipants;
  int? unreadMessages;
  int? pk;
  List<Participants>? participants;

  MessageThreads(
      {this.threadRead,
      this.lastMessage,
      this.lastUpdated,
      this.numberOfParticipants,
      this.unreadMessages,
      this.pk,
      this.participants});

  MessageThreads.fromJson(Map<String, dynamic> json) {
    threadRead = json['thread_read'];
    lastMessage = json['last_message'];
    lastUpdated = json['last_updated'];
    numberOfParticipants = json['number_of_participants'];
    unreadMessages = json['unread_messages'];
    pk = json['pk'];
    if (json['participants'] != null) {
      participants = <Participants>[];
      json['participants'].forEach((v) {
        participants!.add(new Participants.fromJson(v));
      });
    }
  }

  Map<String, dynamic> toJson() {
    final Map<String, dynamic> data = new Map<String, dynamic>();
    data['thread_read'] = this.threadRead;
    data['last_message'] = this.lastMessage;
    data['last_updated'] = this.lastUpdated;
    data['unread_messages'] = this.unreadMessages;
    data['number_of_participants'] = this.numberOfParticipants;
    data['pk'] = this.pk;
    if (this.participants != null) {
      data['participants'] = this.participants!.map((v) => v.toJson()).toList();
    }
    return data;
  }
}

class Participants {
  String? messageThreadId;
  int? pk;
  String? number;
  bool? isSelf;

  /// Server-side join of this participant to a CRM contact. Set when the
  /// participant's phone number matched a saved contact in the account.
  /// Voice360-fe reads `contact.firstname/lastname` to render the row title.
  ParticipantContact? contact;

  Participants({
    this.messageThreadId,
    this.pk,
    this.number,
    this.isSelf,
    this.contact,
  });

  /// Convenience: the contact's first+last as a single trimmed string, or
  /// `null` when no contact is embedded.
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
      contact = ParticipantContact.fromJson(
          raw.cast<String, dynamic>());
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

/// Subset of CRM contact fields the server embeds on a thread participant.
/// We intentionally don't pull the whole [Contact] model in here — it's a
/// huge object with dozens of nullable fields; we only need name + pk to
/// label a thread.
class ParticipantContact {
  int? pk;
  String? firstname;
  String? lastname;
  String? phone;
  String? email;

  ParticipantContact({this.pk, this.firstname, this.lastname, this.phone, this.email});

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
