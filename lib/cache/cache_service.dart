import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:itp_voice/models/call_history_model.dart';
import 'package:itp_voice/models/get_contacts_reponse_model/contact_response.dart';
import 'package:itp_voice/models/get_message_threads_response_model/get_message_threads_response_model.dart';
import 'package:itp_voice/models/get_thread_messages_response_model/get_thread_messages_response_model.dart'
    as tm;
import 'package:itp_voice/models/get_thread_messages_response_model/get_thread_messages_response_model.dart'
    show GetThreadMessagesResponseModel, Messages;
import 'package:itp_voice/models/get_voice_mails_response_model/result.dart';

/// Persistent stale-while-revalidate (SWR) cache for the app's primary data
/// sets: contacts, SMS threads, recent messages per thread, call history,
/// voicemails.
///
/// Model storage strategy: every model is serialised as a JSON-compatible
/// `Map<String, dynamic>` via its `toMap()` / `fromMap()` constructors, and
/// stored in untyped Hive boxes. This avoids the codegen overhead of
/// `hive_generator` and keeps schema migration trivial (just bump the box
/// version).
///
/// Read pattern from a controller:
/// ```dart
/// final cached = AppCache.instance.contacts.readAll();
/// if (cached.isNotEmpty) { /* render immediately */ }
/// fetchFromNetwork().then((fresh) => AppCache.instance.contacts.writeAll(fresh));
/// ```
class AppCache {
  AppCache._();
  static final AppCache instance = AppCache._();

  static const _kBoxContacts = 'v360_contacts_v1';
  static const _kBoxThreads = 'v360_threads_v1';
  static const _kBoxMessages = 'v360_messages_v1';
  static const _kBoxCallHistory = 'v360_call_history_v1';
  static const _kBoxVoicemails = 'v360_voicemails_v1';
  static const _kBoxMeta = 'v360_meta_v1';

  // Public accessors.
  late final ContactsCache contacts = ContactsCache._(_contactsBox, _metaBox);
  late final ThreadsDiskCache threads = ThreadsDiskCache._(_threadsBox, _metaBox);
  late final MessagesDiskCache messages =
      MessagesDiskCache._(_messagesBox, _metaBox);
  late final CallHistoryCache callHistory =
      CallHistoryCache._(_callHistoryBox, _metaBox);
  late final VoicemailsCache voicemails =
      VoicemailsCache._(_voicemailsBox, _metaBox);

  late Box _contactsBox;
  late Box _threadsBox;
  late Box _messagesBox;
  late Box _callHistoryBox;
  late Box _voicemailsBox;
  late Box _metaBox;

  bool _initialised = false;

  Future<void> init() async {
    if (_initialised) return;
    await Hive.initFlutter();
    _contactsBox = await Hive.openBox(_kBoxContacts);
    _threadsBox = await Hive.openBox(_kBoxThreads);
    _messagesBox = await Hive.openBox(_kBoxMessages);
    _callHistoryBox = await Hive.openBox(_kBoxCallHistory);
    _voicemailsBox = await Hive.openBox(_kBoxVoicemails);
    _metaBox = await Hive.openBox(_kBoxMeta);
    _initialised = true;
  }

  bool get isReady => _initialised;

  /// Wipe everything — call on logout.
  Future<void> clearAll() async {
    if (!_initialised) return;
    await Future.wait([
      _contactsBox.clear(),
      _threadsBox.clear(),
      _messagesBox.clear(),
      _callHistoryBox.clear(),
      _voicemailsBox.clear(),
      _metaBox.clear(),
    ]);
  }
}

/// Shared helper that converts deeply-nested model maps to a JSON-safe shape.
/// Hive supports primitives + Lists + Maps, but our models occasionally
/// include `dynamic` fields (e.g. `Contact.address`) that may already be
/// JSON-safe. We trust `toMap()` to produce something serialisable.
Map<String, dynamic> _safeMap(Map<String, dynamic> source) {
  return _convert(source) as Map<String, dynamic>;
}

dynamic _convert(dynamic value) {
  if (value == null) return null;
  if (value is String || value is num || value is bool) return value;
  if (value is DateTime) return value.toIso8601String();
  if (value is List) return value.map(_convert).toList(growable: false);
  if (value is Map) {
    final out = <String, dynamic>{};
    value.forEach((k, v) {
      out[k.toString()] = _convert(v);
    });
    return out;
  }
  // Fallback: anything else, stringify so Hive doesn't choke.
  return value.toString();
}

/// Coerce a Hive-read `Map<dynamic, dynamic>` into `Map<String, dynamic>` so
/// model `fromMap()` constructors don't have to deal with the dynamic key form.
Map<String, dynamic> _normaliseMap(Map raw) {
  final out = <String, dynamic>{};
  raw.forEach((k, v) {
    out[k.toString()] = v is Map ? _normaliseMap(v) : v;
  });
  return out;
}

// ---------------------------------------------------------------------------
// Contacts
// ---------------------------------------------------------------------------

class ContactsCache {
  final Box _box;
  final Box _meta;
  static const _kAllKey = 'all';
  static const _kSyncedAt = 'contacts_synced_at';

  ContactsCache._(this._box, this._meta);

  /// Last successful sync timestamp.
  DateTime? get lastSyncedAt {
    final raw = _meta.get(_kSyncedAt);
    if (raw is String) return DateTime.tryParse(raw);
    return null;
  }

  /// All cached contacts. Empty when nothing has been stored yet.
  List<Contact> readAll() {
    final raw = _box.get(_kAllKey);
    if (raw is! List) return const [];
    final out = <Contact>[];
    for (final entry in raw) {
      if (entry is Map) {
        try {
          out.add(Contact.fromJson(
              _normaliseMap(entry).cast<String, dynamic>()));
        } catch (_) {/* skip corrupt entry */}
      }
    }
    return out;
  }

  /// Replace the cached list. Call after a successful fetch.
  Future<void> writeAll(List<Contact> fresh) async {
    final list = fresh.map((c) => _safeMap(c.toJson())).toList(growable: false);
    await _box.put(_kAllKey, list);
    await _meta.put(_kSyncedAt, DateTime.now().toIso8601String());
  }

  Future<void> remove(int pk) async {
    final list = readAll();
    list.removeWhere((c) => c.pk == pk);
    await writeAll(list);
  }
}

// ---------------------------------------------------------------------------
// Threads (per-from-number)
// ---------------------------------------------------------------------------

class ThreadsDiskCache {
  final Box _box;
  final Box _meta;

  ThreadsDiskCache._(this._box, this._meta);

  String _key(String fromNumber) => 'from:$fromNumber';
  String _syncedKey(String fromNumber) => 'threads_synced:$fromNumber';

  DateTime? lastSyncedAt(String fromNumber) {
    final raw = _meta.get(_syncedKey(fromNumber));
    if (raw is String) return DateTime.tryParse(raw);
    return null;
  }

  List<MessageThreads> read(String fromNumber) {
    if (fromNumber.isEmpty) return const [];
    final raw = _box.get(_key(fromNumber));
    if (raw is! List) return const [];
    final out = <MessageThreads>[];
    for (final entry in raw) {
      if (entry is Map) {
        try {
          out.add(MessageThreads.fromJson(
              _normaliseMap(entry).cast<String, dynamic>()));
        } catch (_) {}
      }
    }
    return out;
  }

  Future<void> write(String fromNumber, List<MessageThreads> fresh) async {
    if (fromNumber.isEmpty) return;
    final list =
        fresh.map((t) => _safeMap(t.toJson())).toList(growable: false);
    await _box.put(_key(fromNumber), list);
    await _meta.put(_syncedKey(fromNumber), DateTime.now().toIso8601String());
  }
}

// ---------------------------------------------------------------------------
// Messages per thread (last N stored)
// ---------------------------------------------------------------------------

class MessagesDiskCache {
  final Box _box;
  final Box _meta;
  static const int _maxPerThread = 100;

  MessagesDiskCache._(this._box, this._meta);

  String _key(String threadId) => 'thread:$threadId';
  String _syncedKey(String threadId) => 'messages_synced:$threadId';

  DateTime? lastSyncedAt(String threadId) {
    final raw = _meta.get(_syncedKey(threadId));
    if (raw is String) return DateTime.tryParse(raw);
    return null;
  }

  GetThreadMessagesResponseModel? read(String threadId) {
    if (threadId.isEmpty) return null;
    final raw = _box.get(_key(threadId));
    if (raw is! Map) return null;
    try {
      return GetThreadMessagesResponseModel.fromJson(
          _normaliseMap(raw).cast<String, dynamic>());
    } catch (e) {
      if (kDebugMode) print('MessagesCache.read deserialise failed: $e');
      return null;
    }
  }

  Future<void> write(
      String threadId, GetThreadMessagesResponseModel model) async {
    if (threadId.isEmpty) return;
    // Trim to last [_maxPerThread] so we don't unbounded-grow.
    final trimmed = _trim(model);
    await _box.put(_key(threadId), _safeMap(trimmed.toJson()));
    await _meta.put(_syncedKey(threadId), DateTime.now().toIso8601String());
  }

  GetThreadMessagesResponseModel _trim(
      GetThreadMessagesResponseModel source) {
    final msgs = source.result?.messages;
    if (msgs == null || msgs.length <= _maxPerThread) return source;
    final keep = msgs.sublist(0, _maxPerThread);
    final trimmedResult = tm.Result(
      messages: keep,
      participants: source.result?.participants,
    );
    return GetThreadMessagesResponseModel(result: trimmedResult);
  }
}

// ---------------------------------------------------------------------------
// Call history
// ---------------------------------------------------------------------------

class CallHistoryCache {
  final Box _box;
  final Box _meta;
  static const _kAllKey = 'all';
  static const _kSyncedAt = 'call_history_synced_at';
  static const _maxEntries = 200;

  CallHistoryCache._(this._box, this._meta);

  DateTime? get lastSyncedAt {
    final raw = _meta.get(_kSyncedAt);
    if (raw is String) return DateTime.tryParse(raw);
    return null;
  }

  List<CallHistory> readAll() {
    final raw = _box.get(_kAllKey);
    if (raw is! List) return const [];
    final out = <CallHistory>[];
    for (final entry in raw) {
      if (entry is Map) {
        try {
          out.add(CallHistory.fromMap(entry));
        } catch (_) {}
      }
    }
    return out;
  }

  Future<void> writeAll(List<CallHistory> fresh) async {
    final trimmed = fresh.length > _maxEntries
        ? fresh.sublist(0, _maxEntries)
        : fresh;
    final list = trimmed.map((c) => c.toMap()).toList(growable: false);
    await _box.put(_kAllKey, list);
    await _meta.put(_kSyncedAt, DateTime.now().toIso8601String());
  }
}

// ---------------------------------------------------------------------------
// Voicemails
// ---------------------------------------------------------------------------

class VoicemailsCache {
  final Box _box;
  final Box _meta;
  static const _kAllKey = 'all';
  static const _kSyncedAt = 'voicemails_synced_at';

  VoicemailsCache._(this._box, this._meta);

  DateTime? get lastSyncedAt {
    final raw = _meta.get(_kSyncedAt);
    if (raw is String) return DateTime.tryParse(raw);
    return null;
  }

  List<VoiceMails> readAll() {
    final raw = _box.get(_kAllKey);
    if (raw is! List) return const [];
    final out = <VoiceMails>[];
    for (final entry in raw) {
      if (entry is Map) {
        try {
          out.add(VoiceMails.fromMap(
              _normaliseMap(entry).cast<String, dynamic>()));
        } catch (_) {}
      }
    }
    return out;
  }

  Future<void> writeAll(List<VoiceMails> fresh) async {
    final list = fresh.map((v) => _safeMap(v.toMap())).toList(growable: false);
    await _box.put(_kAllKey, list);
    await _meta.put(_kSyncedAt, DateTime.now().toIso8601String());
  }

  Future<void> remove(String msgId) async {
    final list = readAll();
    list.removeWhere((v) => v.msgId == msgId);
    await writeAll(list);
  }
}
