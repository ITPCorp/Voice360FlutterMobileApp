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

  /// Best-effort thread id pulled from the payload.
  String? get threadId {
    final t = _parsedPayload?['message_thread_id'] ??
        _parsedPayload?['thread_id'] ??
        event.data['message_thread_pk'] ??
        event.data['thread']?['pk'];
    return t?.toString();
  }

  String? get fromNumber =>
      (event.data['from_number'] ?? _parsedPayload?['from_number'])?.toString();

  String? get toNumber {
    final to = event.data['to_number'] ?? _parsedPayload?['to_number'];
    if (to != null) return to.toString();
    final list = event.data['to_numbers_list'];
    if (list is List && list.isNotEmpty) return list.first?.toString();
    return null;
  }

  String? get body {
    return (event.data['body'] ??
            _parsedPayload?['message_body'] ??
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
      event.data['message_content_id'],
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
      (event.data['provider_message_id'] ??
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
      'message_thread_pk': threadId,
      'message': body ?? '',
      'message_provider_id': providerId,
      'media_id': null,
      'message_timestamp': timestampUtc,
      'from_number': fromNumber,
    };
  }
}
