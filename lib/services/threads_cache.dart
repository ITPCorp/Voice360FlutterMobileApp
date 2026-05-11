import 'package:injectable/injectable.dart';
import 'package:itp_voice/models/get_message_threads_response_model/get_message_threads_response_model.dart';
import 'package:itp_voice/repo/messages_repo.dart';

/// Small per-from-number cache of SMS threads. Lets the chat screen answer
/// "does a thread exist for this peer?" instantly when the user taps Message
/// on a contact, instead of round-tripping every time.
///
/// Two staleness levels:
///  - **Hot** (< [_ttl]): return immediately, no refresh.
///  - **Stale** (anything older): return what we have AND kick off a refresh
///    in the background so the next call is hot.
///
/// Calling [warm] pre-fetches in the background; safe to call from anywhere.
@lazySingleton
class ThreadsCache {
  final MessagesRepo _repo = MessagesRepo();
  static const Duration _ttl = Duration(seconds: 30);

  final Map<String, _Entry> _byNumber = {};
  final Map<String, Future<void>> _inflight = {};

  /// Pre-fetch threads for [fromNumber] without blocking the caller.
  /// Idempotent — multiple concurrent calls collapse into one network request.
  void warm(String fromNumber) {
    if (fromNumber.isEmpty) return;
    final hit = _byNumber[fromNumber];
    if (hit != null && hit.isFresh) return;
    _refresh(fromNumber);
  }

  /// Returns the cached thread list for [fromNumber]. If stale, triggers a
  /// background refresh but still returns the stale snapshot immediately.
  /// Returns `null` when nothing has ever been fetched (and a fetch is now
  /// running — call [get] again shortly).
  List<MessageThreads>? peek(String fromNumber) {
    final hit = _byNumber[fromNumber];
    if (hit == null) {
      _refresh(fromNumber);
      return null;
    }
    if (!hit.isFresh) _refresh(fromNumber);
    return hit.threads;
  }

  /// Like [peek] but awaits a network round-trip when nothing is cached yet.
  Future<List<MessageThreads>> get(String fromNumber) async {
    final hit = _byNumber[fromNumber];
    if (hit != null && hit.isFresh) return hit.threads;
    await _refresh(fromNumber);
    return _byNumber[fromNumber]?.threads ?? const [];
  }

  /// Bypass the cache and force a refresh. Useful right after sending a
  /// message in compose mode, so we can find the brand-new thread.
  Future<void> invalidateAndRefresh(String fromNumber) async {
    _byNumber.remove(fromNumber);
    await _refresh(fromNumber);
  }

  /// Look up a thread by the peer's phone number, normalised to digits-only
  /// (handles "+1 555-..." vs "5551234567"). Returns `null` if no match.
  MessageThreads? findThreadForPeer({
    required String fromNumber,
    required String peerNumber,
  }) {
    final threads = _byNumber[fromNumber]?.threads;
    if (threads == null || threads.isEmpty) return null;
    final wantedDigits = peerNumber.replaceAll(RegExp(r'\D'), '');
    if (wantedDigits.isEmpty) return null;

    for (final t in threads) {
      for (final p in (t.participants ?? const [])) {
        if (p.isSelf == true) continue;
        final candidate = (p.number ?? '').replaceAll(RegExp(r'\D'), '');
        if (candidate.isEmpty) continue;
        if (candidate == wantedDigits ||
            candidate.endsWith(wantedDigits) ||
            wantedDigits.endsWith(candidate)) {
          return t;
        }
      }
    }
    return null;
  }

  /// Replace the cached threads — call when the Messages screen has just
  /// fetched fresh data so we don't refetch immediately.
  void prime(String fromNumber, List<MessageThreads> threads) {
    if (fromNumber.isEmpty) return;
    _byNumber[fromNumber] =
        _Entry(threads: List.unmodifiable(threads), fetchedAt: DateTime.now());
  }

  Future<void> _refresh(String fromNumber) {
    final existing = _inflight[fromNumber];
    if (existing != null) return existing;
    final future = _doFetch(fromNumber);
    _inflight[fromNumber] = future;
    future.whenComplete(() => _inflight.remove(fromNumber));
    return future;
  }

  Future<void> _doFetch(String fromNumber) async {
    try {
      final res = await _repo.getMessageThreads(fromNumber);
      if (res is GetMessageThreadsResponseModel) {
        _byNumber[fromNumber] = _Entry(
          threads: List.unmodifiable(res.result?.messageThreads ?? const []),
          fetchedAt: DateTime.now(),
        );
      }
    } catch (_) {
      // Swallow; next call retries.
    }
  }
}

class _Entry {
  final List<MessageThreads> threads;
  final DateTime fetchedAt;
  _Entry({required this.threads, required this.fetchedAt});
  bool get isFresh => DateTime.now().difference(fetchedAt) < ThreadsCache._ttl;
}
