import 'dart:async';
import 'dart:convert';

import 'package:itp_voice/repo/shares_preference_repo.dart';
import 'package:itp_voice/storage_keys.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

/// A normalized SMS/call event from the global notification socket.
///
/// We translate the web's nested
/// `{type: notification, data: {content: {type: sms.received, data: {...}}}}`
/// shape into something the controllers can consume directly.
class GlobalSocketEvent {
  /// Raw outer wrapper type (eg. `notification`, `account.event`, `ping`).
  final String outerType;

  /// Inner content type (eg. `sms.received`, `sms.sent`, `sms`,
  /// or null when the outer event has no `content`).
  final String? innerType;

  /// Inner data payload — for SMS events this is `content.data`.
  final Map<String, dynamic> data;

  GlobalSocketEvent({
    required this.outerType,
    this.innerType,
    required this.data,
  });

  bool get isSmsReceived => innerType == 'sms.received';
  bool get isSmsSent => innerType == 'sms.sent';
  bool get isSmsGeneric => innerType == 'sms';
  bool get isAnySms => isSmsReceived || isSmsSent || isSmsGeneric;
}

/// Long-lived WebSocket connection to the platform's global notification
/// stream. Matches the web client's `globalWebSocketService.jsx` — same
/// endpoint, auth shape, ping cadence, and event types.
///
/// Lifecycle:
///   * call [connect] once after login lands on the base screen
///   * subscribe to [events] from whichever controllers want updates
///   * call [disconnect] on logout
class GlobalSocketService {
  static const _wsBase = 'wss://ws.cloud.itp360.com/ws';
  static const _pingInterval = Duration(seconds: 30);
  static const _baseReconnectDelay = Duration(seconds: 5);
  static const _maxReconnectDelay = Duration(seconds: 60);

  WebSocketChannel? _channel;
  StreamSubscription? _channelSub;
  Timer? _pingTimer;
  Timer? _reconnectTimer;
  bool _shouldReconnect = false;
  int _retries = 0;

  final StreamController<GlobalSocketEvent> _events =
      StreamController<GlobalSocketEvent>.broadcast();

  /// Broadcast stream of normalized events. Late subscribers don't get
  /// historical events — only what arrives while subscribed.
  Stream<GlobalSocketEvent> get events => _events.stream;

  bool get isConnected => _channel != null;

  /// Connect using whatever auth+ids are currently in SharedPreferences.
  /// Safe to call multiple times — no-ops if already connected.
  Future<void> connect() async {
    if (_channel != null) return;

    final token = SharedPreferencesMethod.storage.getString(StorageKeys.REFRESH_TOKEN);
    final accountId = SharedPreferencesMethod.storage.getString(StorageKeys.API_ID);
    final userId = SharedPreferencesMethod.storage.getString(StorageKeys.USER_ID);

    if (token == null || token.isEmpty ||
        accountId == null || accountId.isEmpty ||
        userId == null || userId.isEmpty) {
      // Auth not ready yet. Caller can retry after login completes.
      return;
    }

    _shouldReconnect = true;
    _open(token: token, accountId: accountId, userId: userId);
  }

  void _open({
    required String token,
    required String accountId,
    required String userId,
  }) {
    final uri = Uri.parse(_wsBase).replace(queryParameters: {
      'token': token,
      'service': 'voice360',
      'account_id': accountId,
      'user_id': userId,
    });

    try {
      // ignore: avoid_print
      print('[GlobalSocket] connecting to $_wsBase (account=$accountId, user=$userId)');
      final channel = WebSocketChannel.connect(uri);
      _channel = channel;
      _startPing();
      _channelSub = channel.stream.listen(
        _handleRaw,
        onDone: () {
          // ignore: avoid_print
          print('[GlobalSocket] disconnected');
          _onDone();
        },
        onError: (e, _) {
          // ignore: avoid_print
          print('[GlobalSocket] error: $e');
          _onDone();
        },
        cancelOnError: true,
      );
    } catch (e) {
      // ignore: avoid_print
      print('[GlobalSocket] open error: $e');
      _scheduleReconnect();
    }
  }

  void _handleRaw(dynamic raw) {
    _retries = 0;
    if (raw is! String) return;
    Map<String, dynamic> body;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return;
      body = decoded;
    } catch (_) {
      return;
    }

    final outerType = body['type']?.toString() ?? '';
    // Server pings expect a pong back.
    if (outerType == 'ping') {
      _send({'type': 'pong'});
      return;
    }

    // Pull out content.type / content.data when present (notification events).
    final outerData = body['data'];
    String? innerType;
    Map<String, dynamic> innerData = const {};
    if (outerData is Map<String, dynamic>) {
      final content = outerData['content'];
      if (content is Map<String, dynamic>) {
        innerType = content['type']?.toString();
        final cd = content['data'];
        if (cd is Map<String, dynamic>) innerData = cd;
      } else {
        innerData = outerData;
      }
    }

    _events.add(GlobalSocketEvent(
      outerType: outerType,
      innerType: innerType,
      data: innerData,
    ));
  }

  void _send(Map<String, dynamic> payload) {
    try {
      _channel?.sink.add(jsonEncode(payload));
    } catch (_) {}
  }

  void _startPing() {
    _pingTimer?.cancel();
    _pingTimer = Timer.periodic(_pingInterval, (_) {
      _send({'type': 'ping'});
    });
  }

  void _onDone() {
    _channelSub?.cancel();
    _channelSub = null;
    _pingTimer?.cancel();
    _pingTimer = null;
    try {
      _channel?.sink.close();
    } catch (_) {}
    _channel = null;
    if (_shouldReconnect) _scheduleReconnect();
  }

  void _scheduleReconnect() {
    _reconnectTimer?.cancel();
    _retries++;
    final delayMs = _baseReconnectDelay.inMilliseconds *
        (1 << (_retries.clamp(0, 4))); // exponential up to ~80s
    final delay = Duration(
      milliseconds: delayMs.clamp(
        _baseReconnectDelay.inMilliseconds,
        _maxReconnectDelay.inMilliseconds,
      ),
    );
    _reconnectTimer = Timer(delay, () {
      if (!_shouldReconnect) return;
      connect();
    });
  }

  /// Permanently tear down. Call on logout.
  Future<void> disconnect() async {
    _shouldReconnect = false;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _pingTimer?.cancel();
    _pingTimer = null;
    await _channelSub?.cancel();
    _channelSub = null;
    try {
      await _channel?.sink.close();
    } catch (_) {}
    _channel = null;
  }
}

/// Helpers that extract SMS fields from the multiple payload shapes the
/// backend may send. Mirrors what RealChatContainer.jsx does on the web.
class SmsEventReader {
  final GlobalSocketEvent event;
  Map<String, dynamic>? _parsedPayload;

  SmsEventReader(this.event) {
    final payload = event.data['payload'];
    if (payload is String && payload.isNotEmpty) {
      try {
        final decoded = jsonDecode(payload);
        if (decoded is Map<String, dynamic>) _parsedPayload = decoded;
      } catch (_) {}
    } else if (payload is Map<String, dynamic>) {
      _parsedPayload = payload;
    }
  }

  /// [key] from the event, looking in the flat data, its `metadata` block
  /// and the decoded `payload`, in that order. voice-api puts the group
  /// fields (thread_id, owner_number, participants) in the event metadata.
  dynamic _field(String key) {
    final direct = event.data[key];
    if (direct != null) return direct;
    final meta = event.data['metadata'];
    if (meta is Map && meta[key] != null) return meta[key];
    return _parsedPayload?[key];
  }

  /// Best-effort thread id pulled from the payload. thread_id is the
  /// group-aware id (full participant set), so it goes first.
  String? get threadId {
    final t = _field('thread_id') ??
        _parsedPayload?['message_thread_id'] ??
        event.data['message_thread_pk'] ??
        event.data['thread']?['pk'] ??
        event.data['thread']?['id'];
    final s = t?.toString();
    return (s == null || s.isEmpty || s == 'null') ? null : s;
  }

  String? get fromNumber => _field('from_number')?.toString();

  /// Every recipient on the event. SMS_DELIVERED carries the list under
  /// `to_number`, SMS_RECEIVED under `to_numbers_list`.
  List<String> get toNumbers {
    final out = <String>[];
    for (final key in const ['to_numbers_list', 'to_number']) {
      final v = _field(key);
      if (v is List) {
        out.addAll(v.where((e) => e != null).map((e) => e.toString()));
      } else if (v != null && v.toString().isNotEmpty) {
        out.add(v.toString());
      }
    }
    return out;
  }

  /// First recipient, kept for callers that only know about 1:1.
  String? get toNumber {
    final list = toNumbers;
    return list.isEmpty ? null : list.first;
  }

  /// The Voice360 number this copy of the event is for: owner_number when
  /// the backend sends it, else the old guess (our number is the sender on
  /// sms.sent, the first recipient on sms.received).
  String? get ownerNumber {
    final owner = _field('owner_number')?.toString();
    if (owner != null && owner.isNotEmpty) return owner;
    return event.isSmsSent ? fromNumber : toNumber;
  }

  /// [ownerNumber], except that without owner_number an inbound group text
  /// lists several to-numbers and ours may not be the first one: prefer the
  /// recipient equal to [mine].
  String? ownerNumberFor(String mine) {
    final owner = _field('owner_number')?.toString();
    if (owner != null && owner.isNotEmpty) return owner;
    if (!event.isSmsSent && mine.isNotEmpty) {
      final digits = mine.replaceAll(RegExp(r'\D'), '');
      for (final n in toNumbers) {
        final d = n.replaceAll(RegExp(r'\D'), '');
        if (d.isNotEmpty && (d.endsWith(digits) || digits.endsWith(d))) {
          return n;
        }
      }
    }
    return ownerNumber;
  }

  /// Full participant set of the thread, sender included, as numbers.
  /// Entries can be bare numbers or {number, is_self, ...} objects.
  List<String> get participantNumbers {
    final v = _field('participants');
    if (v is! List) return const [];
    final out = <String>[];
    for (final p in v) {
      final n = p is Map ? p['number'] : p;
      if (n != null && n.toString().isNotEmpty) out.add(n.toString());
    }
    return out;
  }

  String? get body {
    return (event.data['body'] ??
            _field('sms_body') ??
            _field('message_body') ??
            _parsedPayload?['message'] ??
            event.data['thread']?['last_message'])
        ?.toString();
  }

  String? get messageContentId =>
      (event.data['message_content_id'] ??
              _parsedPayload?['message_content_id'] ??
              _parsedPayload?['id'] ??
              event.data['sms_id'] ??
              _parsedPayload?['sms_id'])
          ?.toString();

  /// Numeric pk of the SMS row (when the payload exposes it). Used to match
  /// against the locally-inserted outbound bubble after a POST.
  int? get messagePk {
    final candidates = [
      _parsedPayload?['id'],
      _parsedPayload?['pk'],
      _field('message_content_id'),
      _parsedPayload?['message_content_id'],
    ];
    for (final c in candidates) {
      if (c is int) return c;
      if (c is num) return c.toInt();
      if (c is String) {
        final n = int.tryParse(c);
        if (n != null) return n;
      }
    }
    return null;
  }

  String? get providerId =>
      (_field('provider_message_id') ??
              _parsedPayload?['message_provider_id'] ??
              _parsedPayload?['provider_message_id'])
          ?.toString();

  String? get status =>
      (event.data['status'] ??
              _parsedPayload?['message_status'] ??
              _parsedPayload?['status'])
          ?.toString();

  String? get timestampUtc =>
      (event.data['message_timestamp_utc'] ??
              _parsedPayload?['message_timestamp'] ??
              event.data['thread']?['last_updated'])
          ?.toString();

  /// Build a payload shape compatible with `Messages.fromPayload` so we
  /// can reuse the existing insertion logic in ChatController.
  Map<String, dynamic> toLegacyPayload() {
    return {
      'message_status': null,
      'pk': messagePk,
      'message_thread_pk': threadId,
      'message': body ?? '',
      'message_provider_id': providerId,
      'media_id': null,
      'message_timestamp': timestampUtc,
      'from_number': fromNumber,
    };
  }
}
