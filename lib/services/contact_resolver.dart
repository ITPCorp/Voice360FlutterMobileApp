import 'package:itp_voice/cache/cache_service.dart';
import 'package:itp_voice/models/get_contacts_reponse_model/contact_response.dart';
import 'package:itp_voice/models/get_message_threads_response_model/get_message_threads_response_model.dart'
    as thr;

/// Resolves the best human-readable name for an SMS thread / call peer.
///
/// Resolution order:
///   1. **Server-side join**: when the thread's non-self participant has an
///      embedded `contact` object, use `contact.firstname/lastname`.
///   2. **Local contacts cache**: match by phone (digits-only suffix) against
///      the user's CRM contacts, already persisted to disk.
///   3. **Fallback**: the raw phone number string.
///
/// This is intentionally synchronous + cheap — both lookups read from in-
/// memory data we've already loaded. Safe to call once per list row.
class ContactResolver {
  ContactResolver._();

  /// Resolved name for a thread row in the Messages list. Returns the phone
  /// number if no match.
  static String resolveThreadDisplay(thr.MessageThreads thread) {
    final peer = _peerOf(thread);
    if (peer == null) return _phoneOf(thread) ?? 'Unknown';
    final embedded = peer.contactName;
    if (embedded != null && embedded.isNotEmpty) return embedded;
    final local = _matchLocalByPhone(peer.number);
    if (local != null) return local;
    return peer.number ?? 'Unknown';
  }

  /// Same logic, but for an arbitrary phone string — used by the chat header
  /// and contact-tap-to-message flow.
  static String resolveByPhone(String? phone, {String fallback = 'Unknown'}) {
    if (phone == null || phone.isEmpty) return fallback;
    final local = _matchLocalByPhone(phone);
    if (local != null) return local;
    return phone;
  }

  /// Lighter wrapper: returns just the embedded-or-local name, or `null`
  /// when nothing matched. Useful when the caller wants to *avoid* falling
  /// back to the phone number (e.g. for an avatar's initials).
  static String? resolveNameOrNull(String? phone) {
    if (phone == null || phone.isEmpty) return null;
    return _matchLocalByPhone(phone);
  }

  // -------------------------------------------------------------------------
  // Internals
  // -------------------------------------------------------------------------

  static thr.Participants? _peerOf(thr.MessageThreads thread) {
    final list = thread.participants;
    if (list == null || list.isEmpty) return null;
    for (final p in list) {
      if (p.isSelf != true) return p;
    }
    return list.first;
  }

  static String? _phoneOf(thr.MessageThreads thread) {
    return _peerOf(thread)?.number;
  }

  /// Normalise to digits-only, dropping leading country-code padding so
  /// "+15551234567" and "5551234567" still match.
  static String _digits(String s) => s.replaceAll(RegExp(r'\D'), '');

  static String? _matchLocalByPhone(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    if (!AppCache.instance.isReady) return null;
    final wanted = _digits(raw);
    if (wanted.isEmpty) return null;

    for (final c in AppCache.instance.contacts.readAll()) {
      final candidate = _digits(c.phone ?? '');
      if (candidate.isEmpty) continue;
      // Suffix match handles ±country-code differences.
      if (candidate == wanted ||
          candidate.endsWith(wanted) ||
          wanted.endsWith(candidate)) {
        final name = _formatName(c);
        if (name != null) return name;
      }
    }
    return null;
  }

  static String? _formatName(Contact c) {
    final full = ('${c.firstname ?? ''} ${c.lastname ?? ''}').trim();
    return full.isEmpty ? null : full;
  }
}
