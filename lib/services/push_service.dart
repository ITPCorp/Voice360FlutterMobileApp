import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:get/get.dart';
import 'package:itp_voice/main.dart' show firebaseReady;
import 'package:itp_voice/routes.dart';

/// Centralized push-notification pipeline. Replaces the per-screen FCM
/// listeners that lived in LoginScreen / ChatController.
///
/// Lifecycle:
///   * `initialize()` is called once from `main()` (after Firebase init).
///   * `onLoginSuccess()` is called by AuthRepo when login completes so we
///     can request OS permission and refresh the registered token.
///   * `onLogout()` clears state.
///
/// What it does:
///   * Foreground messages → display a banner via flutter_local_notifications,
///     unless the user is currently sitting in the matching chat screen.
///   * Background/tap messages → route to the chat screen.
///   * Cold launch from a notification → route once the routing stack is ready.
///   * Tap on a locally-shown foreground banner → route to the chat screen.
class PushService {
  static const _androidChannelId = 'itpvoice';
  static const _androidChannelName = 'VOICE360';
  static const _androidChannelDescription = 'Calls, messages, and voicemail';

  final FlutterLocalNotificationsPlugin _localNotifs =
      FlutterLocalNotificationsPlugin();

  bool _initialized = false;
  String? _cachedToken;
  String? get cachedToken => _cachedToken;

  StreamSubscription<RemoteMessage>? _onMessageSub;
  StreamSubscription<RemoteMessage>? _onMessageOpenedAppSub;
  StreamSubscription<String>? _onTokenRefreshSub;

  /// One-time setup: notification channel, plugin init, listener wiring.
  /// Safe to call without Firebase being ready (will no-op the FCM parts).
  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;

    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosInit = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );
    await _localNotifs.initialize(
      const InitializationSettings(android: androidInit, iOS: iosInit),
      onDidReceiveNotificationResponse: (resp) {
        _routeFromPayload(resp.payload);
      },
    );

    // Create the Android channel up front so the first notification doesn't
    // show as a low-importance one.
    if (Platform.isAndroid) {
      await _localNotifs
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.createNotificationChannel(const AndroidNotificationChannel(
            _androidChannelId,
            _androidChannelName,
            description: _androidChannelDescription,
            importance: Importance.high,
          ));
    }

    // Wire FCM listeners. If Firebase isn't actually ready, each call throws
    // synchronously and we no-op the rest of init. The `firebaseReady` flag
    // can desync vs the native init, so we trust the SDK over the flag.
    try {
      _onMessageSub =
          FirebaseMessaging.onMessage.listen(_handleForegroundMessage);
      _onMessageOpenedAppSub = FirebaseMessaging.onMessageOpenedApp
          .listen(_handleOpenedFromBackground);
      _onTokenRefreshSub =
          FirebaseMessaging.instance.onTokenRefresh.listen((newToken) {
        _cachedToken = newToken;
        // ignore: avoid_print
        print('[Push] token refreshed: $newToken');
      });

      // Cold-launched from a tapped notification.
      final initialMessage =
          await FirebaseMessaging.instance.getInitialMessage();
      if (initialMessage != null) {
        // Defer one frame so the navigator is ready.
        Future.delayed(const Duration(milliseconds: 500), () {
          _routeFromRemoteMessage(initialMessage);
        });
      }

      _cachedToken = await FirebaseMessaging.instance.getToken();
      // ignore: avoid_print
      print('[Push] initial token: $_cachedToken');
    } catch (e) {
      // ignore: avoid_print
      print('[Push] init listener wiring failed: $e');
    }
  }

  /// Request push permission (iOS, Android 13+) and grab the current token.
  /// Call after a successful login so the token can be sent to the backend.
  Future<String?> onLoginSuccess() async {
    return _fetchTokenWithRetry();
  }

  /// Attempt to get a current FCM token, defensively re-initializing Firebase
  /// if the SDK reports `[core/no-app]`. The Android FirebaseInitProvider
  /// auto-init occasionally desyncs vs the Dart-side Firebase plugin (we've
  /// observed it after long idle periods on the emulator). Retrying once
  /// after an explicit `Firebase.app()` probe recovers it.
  Future<String?> _fetchTokenWithRetry() async {
    for (var attempt = 0; attempt < 2; attempt++) {
      try {
        await FirebaseMessaging.instance.requestPermission(
          alert: true,
          badge: true,
          sound: true,
        );
        // On iOS, FCM can only produce a token after APNs has registered
        // the device. Wait briefly for the APNs token before asking FCM
        // for a token, otherwise getToken() throws "apns-token-not-set".
        if (Platform.isIOS) {
          for (var i = 0; i < 10; i++) {
            final apns = await FirebaseMessaging.instance.getAPNSToken();
            if (apns != null) break;
            await Future.delayed(const Duration(milliseconds: 500));
          }
        }
        final token = await FirebaseMessaging.instance.getToken();
        _cachedToken = token;
        // ignore: avoid_print
        print('[Push] post-login token: $token');
        return token;
      } catch (e) {
        // ignore: avoid_print
        print('[Push] getToken attempt ${attempt + 1} failed: $e');
        // Only retry once and only for the no-app race.
        if (attempt == 0 && e.toString().toLowerCase().contains('no-app')) {
          try {
            Firebase.app(); // touch-or-throw
          } catch (_) {
            // No app registered. Caller (main.dart) should have already
            // initialized; if not, we can't help here.
          }
        } else {
          return null;
        }
      }
    }
    return null;
  }

  /// Drop local state and ask FCM to delete the token so a stale device
  /// doesn't keep receiving pushes after logout.
  Future<void> onLogout() async {
    _cachedToken = null;
    try {
      await FirebaseMessaging.instance.deleteToken();
    } catch (_) {}
  }

  Future<void> dispose() async {
    await _onMessageSub?.cancel();
    await _onMessageOpenedAppSub?.cancel();
    await _onTokenRefreshSub?.cancel();
  }

  // ──────────────────────────────────────────────────────────────────
  // FCM → UI
  // ──────────────────────────────────────────────────────────────────

  Future<void> _handleForegroundMessage(RemoteMessage message) async {
    final threadId = _extractThreadId(message);
    // Don't double-display if user is already inside the matching chat.
    if (threadId != null &&
        Get.currentRoute == Routes.CHAT_SCREEN_ROUTE &&
        _argsThreadId() == threadId) {
      return;
    }

    final n = message.notification;
    final title = n?.title ?? message.data['title']?.toString() ?? 'New message';
    final body = n?.body ?? message.data['body']?.toString() ?? '';

    await _localNotifs.show(
      message.hashCode,
      title,
      body,
      const NotificationDetails(
        android: AndroidNotificationDetails(
          _androidChannelId,
          _androidChannelName,
          channelDescription: _androidChannelDescription,
          importance: Importance.high,
          priority: Priority.high,
        ),
        iOS: DarwinNotificationDetails(),
      ),
      payload: jsonEncode(message.data),
    );
  }

  void _handleOpenedFromBackground(RemoteMessage message) {
    _routeFromRemoteMessage(message);
  }

  void _routeFromRemoteMessage(RemoteMessage message) {
    final data = message.data;
    final threadId = _extractThreadId(message);
    if (threadId == null) return;
    final toNumber = _extractToNumber(message);
    _navigateToThread(threadId: threadId, toPhoneNumber: toNumber, fromNumber: data['from_number']?.toString());
  }

  void _routeFromPayload(String? payload) {
    if (payload == null || payload.isEmpty) return;
    try {
      final data = jsonDecode(payload);
      if (data is! Map) return;
      final threadId = _readThreadIdFromMap(Map<String, dynamic>.from(data));
      if (threadId == null) return;
      final to = _readToNumberFromMap(Map<String, dynamic>.from(data));
      _navigateToThread(threadId: threadId, toPhoneNumber: to, fromNumber: data['from_number']?.toString());
    } catch (_) {}
  }

  void _navigateToThread({
    required String threadId,
    String? toPhoneNumber,
    String? fromNumber,
  }) {
    // ignore: avoid_print
    print('[Push] navigate → thread=$threadId to=$toPhoneNumber from=$fromNumber');
    // If we're already sitting in a chat screen (possibly for a different
    // thread), Get.toNamed against the same route silently no-ops the
    // initState path → ChatController is reused and Get.arguments is never
    // re-parsed. Pop the existing chat first so the next push mounts a
    // fresh _ChatScreenState (which then force-replaces the controller).
    if (Get.currentRoute == Routes.CHAT_SCREEN_ROUTE) {
      Get.until((route) => route.settings.name != Routes.CHAT_SCREEN_ROUTE);
    }
    Get.toNamed(
      Routes.CHAT_SCREEN_ROUTE,
      arguments: [threadId, toPhoneNumber, fromNumber],
    );
  }

  // ──────────────────────────────────────────────────────────────────
  // Payload extraction
  //
  // Backend (itp-voice-api → itp-crm-api) packs the SMS push as:
  //   notification: { title, body }
  //   data: {
  //     service_name: 'itp_voice',
  //     service_id: <account_id>,
  //     message: <sms body>,
  //     metadata: "{'message_thread_id': 489286, 'to_phone_number': '+1...'}"
  //   }
  // `metadata` is a Python-stringified dict (single quotes!) because the
  // server runs `str(metadata)` before send. Tolerate both Python-str and JSON.
  // ──────────────────────────────────────────────────────────────────

  String? _extractThreadId(RemoteMessage m) =>
      _readThreadIdFromMap(m.data);

  String? _extractToNumber(RemoteMessage m) =>
      _readToNumberFromMap(m.data);

  String? _readThreadIdFromMap(Map<String, dynamic> data) {
    // Newer / cleaner payloads may set the field directly.
    final direct = data['message_thread_id']?.toString();
    if (direct != null && direct.isNotEmpty) return direct;
    final meta = _decodeMetadata(data['metadata']);
    return meta?['message_thread_id']?.toString();
  }

  String? _readToNumberFromMap(Map<String, dynamic> data) {
    final direct = data['to_phone_number']?.toString();
    if (direct != null && direct.isNotEmpty) return direct;
    final meta = _decodeMetadata(data['metadata']);
    return meta?['to_phone_number']?.toString();
  }

  Map<String, dynamic>? _decodeMetadata(dynamic raw) {
    if (raw == null) return null;
    if (raw is Map) return Map<String, dynamic>.from(raw);
    if (raw is String) {
      // Try real JSON first.
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map) return Map<String, dynamic>.from(decoded);
      } catch (_) {}
      // Fall back to Python-stringified dict: {'k': 'v', 'n': 42}
      // Convert single-quotes → double-quotes and re-parse.
      try {
        final fixed = raw
            .replaceAll(RegExp(r"'"), '"')
            .replaceAll('None', 'null')
            .replaceAll('True', 'true')
            .replaceAll('False', 'false');
        final decoded = jsonDecode(fixed);
        if (decoded is Map) return Map<String, dynamic>.from(decoded);
      } catch (_) {}
    }
    return null;
  }

  /// Best-effort lookup of the thread id from the current Get route arguments
  /// — used to suppress the foreground banner when the user is already
  /// looking at the matching chat. We're lenient about shape since chat
  /// arguments evolved over time.
  String? _argsThreadId() {
    final args = Get.arguments;
    if (args is List && args.isNotEmpty) {
      final first = args.first;
      if (first == null) return null;
      return first.toString();
    }
    return null;
  }
}
