import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:get/get.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:itp_voice/services/notification_inbox.dart';
import 'package:itp_voice/controllers/chat_controller.dart';
import 'package:itp_voice/controllers/voicemails_controller.dart';
import 'package:itp_voice/services/notification_destination.dart';
import 'package:itp_voice/services/global_socket_service.dart';
import 'package:itp_voice/controllers/base_screen_controller.dart';
import 'package:itp_voice/repo/auth_repo.dart';
import 'package:itp_voice/routes.dart';
import 'package:itp_voice/services/app_wake/call_wake_service.dart';
import 'package:itp_voice/storage_keys.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
  StreamSubscription<GlobalSocketEvent>? _mailboxSub;

  void watchMailbox(Stream<GlobalSocketEvent> events) {
    _mailboxSub ??= events
        .where((e) => e.innerType == 'voicemail.received')
        .listen((event) {
      final payload = {
        'type': 'voicemail',
        'msg_id': event.data['msg_id'],
        'voicemail_id': event.data['voicemail_id'],
      };
      final target = NotificationDestination.parse(payload);
      if (target?.id == null) return;
      _showBanner('New voicemail', 'Tap to open the recording.', payload,
          Object.hash('voicemail', target!.id) & 0x7fffffff);
    });
  }

  /// Notification tap that arrived before the user reached BaseScreen
  /// (cold launch sits on LoginScreen for ~3s of auto-login). ChatScreen
  /// needs BaseScreenController, so pushing it early throws and leaves a
  /// gray error page that also blocks the auto-login redirect.
  NotificationDestination? _pending;
  bool _homeReady = false;
  int _generation = 0;
  static const _nativeTaps = MethodChannel('voice360/notification_taps');

  /// One-time setup: notification channel, plugin init, listener wiring.
  /// Safe to call without Firebase being ready (will no-op the FCM parts).
  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;

    const androidInit = AndroidInitializationSettings('ic_stat_voice360');
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

    final launch = await _localNotifs.getNotificationAppLaunchDetails();
    if (launch?.didNotificationLaunchApp == true) {
      _routeFromPayload(launch?.notificationResponse?.payload);
    }
    if (Platform.isAndroid) {
      _nativeTaps.setMethodCallHandler((call) async {
        if (call.method == 'available') await _takeNativeTap();
      });
      await _takeNativeTap();
    }

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
        _resyncTokens('fcm token refreshed');
      });

      // Cold-launched from a tapped notification.
      final initialMessage =
          await FirebaseMessaging.instance.getInitialMessage();
      if (initialMessage != null) {
        _routeFromRemoteMessage(initialMessage);
      }

      _cachedToken = await FirebaseMessaging.instance.getToken();
      // ignore: avoid_print
      print('[Push] initial token: $_cachedToken');
    } catch (e) {
      // ignore: avoid_print
      print('[Push] init listener wiring failed: $e');
    }
  }

  StreamSubscription<String>? _voipSub;

  /// App-wake: a new PushKit token (iOS) or FCM token has to reach the CRM
  /// right away, not at the next login. /auth/refresh carries both.
  void watchCallTokens() {
    _voipSub ??= CallWakeService.instance.voipTokenChanges
        .listen((_) => _resyncTokens('voip token changed'));
  }

  Future<void> _resyncTokens(String why) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final t = prefs.getString(StorageKeys.REFRESH_TOKEN);
      if (t == null || t.isEmpty) return;
      // ignore: avoid_print
      print('[Push] $why, sending tokens with /auth/refresh');
      await AuthRepo().refreshSession();
    } catch (e) {
      // ignore: avoid_print
      print('[Push] token resync failed: $e');
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
    await _mailboxSub?.cancel();
    _mailboxSub = null;
    _cachedToken = null;
    _pending = null;
    _homeReady = false;
    _generation++;
    try {
      await FirebaseMessaging.instance.deleteToken();
    } catch (_) {}
  }

  Future<void> dispose() async {
    await _mailboxSub?.cancel();
    await _onMessageSub?.cancel();
    await _onMessageOpenedAppSub?.cancel();
    await _onTokenRefreshSub?.cancel();
  }

  // ──────────────────────────────────────────────────────────────────
  // FCM → UI
  // ──────────────────────────────────────────────────────────────────

  Map<String, dynamic> _tapPayload(RemoteMessage message) => {
        if (message.notification?.title != null)
          'title': message.notification!.title,
        ...message.data,
      };

  Future<void> _handleForegroundMessage(RemoteMessage message) async {
    // Call pushes are handled natively (AppWakeMessagingService); never show
    // them as a message banner.
    if (message.data['type'] == 'voice360_call') return;
    final payload = _tapPayload(message);
    final destination = NotificationDestination.parse(payload);
    final threadId = destination?.screen == NotificationScreen.thread
        ? destination?.id
        : null;
    // Don't double-display if user is already inside the matching chat.
    if (threadId != null &&
        Get.currentRoute == Routes.CHAT_SCREEN_ROUTE &&
        ChatController.visibleThreadId == threadId) {
      return;
    }

    final n = message.notification;
    final title =
        n?.title ?? message.data['title']?.toString() ?? 'New message';
    final body = n?.body ?? message.data['body']?.toString() ?? '';

    final id = destination?.screen == NotificationScreen.voicemail
        ? Object.hash('voicemail', destination?.id) & 0x7fffffff
        : message.hashCode;
    await _showBanner(title, body, payload, id);
  }

  Future<void> _showBanner(
      String title, String body, Map<String, dynamic> data, int id) async {
    await _localNotifs.show(
      id,
      title,
      body,
      NotificationDetails(
        android: AndroidNotificationDetails(
          _androidChannelId,
          _androidChannelName,
          channelDescription: _androidChannelDescription,
          tag: NotificationInbox.androidTag(NotificationDestination.parse(data)),
          autoCancel: true,
          largeIcon: const DrawableResourceAndroidBitmap('notification_voice360'),
          importance: Importance.high,
          priority: Priority.high,
        ),
        iOS: const DarwinNotificationDetails(),
      ),
      payload: jsonEncode(data),
    );
  }

  void _handleOpenedFromBackground(RemoteMessage message) {
    _routeFromRemoteMessage(message);
  }

  void _routeFromRemoteMessage(RemoteMessage message) {
    handleTap(_tapPayload(message));
  }

  void _routeFromPayload(String? payload) {
    if (payload == null) return;
    try {
      final data = jsonDecode(payload);
      if (data is Map) handleTap(data);
    } on FormatException {
      // An old notification can outlive the app version that created it.
    }
  }

  Future<void> _takeNativeTap() async {
    try {
      final data = await _nativeTaps.invokeMapMethod<String, dynamic>('take');
      if (data != null) handleTap(data);
    } on MissingPluginException {
      // No Android activity attached to a background engine yet.
    }
  }

  void handleTap(Map<Object?, Object?> payload) {
    final destination = NotificationDestination.parse(payload);
    if (destination == null) return;
    _generation++;
    _pending = destination;
    if (_homeReady) _openPending();
  }

  void flushPendingNavigation() {
    _homeReady = true;
    _openPending();
  }

  Future<void> _openPending() async {
    final target = _pending;
    if (target == null || !Get.isRegistered<BaseScreenController>()) return;
    _pending = null;
    final generation = _generation;
    final base = Get.find<BaseScreenController>();
    if (target.screen == NotificationScreen.thread &&
        Get.currentRoute == Routes.CHAT_SCREEN_ROUTE &&
        ChatController.visibleThreadId == target.id) {
      NotificationInbox.thread(target.id);
      return;
    }
    Get.until((r) => r.settings.name == Routes.BASE_SCREEN_ROUTE || r.isFirst);
    switch (target.screen) {
      case NotificationScreen.recent:
        base.showMissedCall(target);
        break;
      case NotificationScreen.messages:
        base.updateCurrentTab(2);
        break;
      case NotificationScreen.thread:
        base.updateCurrentTab(2);
        Get.toNamed(Routes.CHAT_SCREEN_ROUTE,
            preventDuplicates: false,
            arguments: [target.id, target.number, target.peer]);
        break;
      case NotificationScreen.voicemail:
        base.updateCurrentTab(3);
        if (target.id == null) return;
        await WidgetsBinding.instance.endOfFrame;
        if (generation != _generation ||
            base.currentTab.value != 3 ||
            Get.currentRoute != Routes.BASE_SCREEN_ROUTE) {
          return;
        }
        final mailbox = Get.find<VoiceMailsController>();
        final match = await mailbox.findNotificationMessage(target.id!,
            recordPk: target.recordPk);
        if (generation != _generation ||
            base.currentTab.value != 3 ||
            Get.currentRoute != Routes.BASE_SCREEN_ROUTE) {
          return;
        }
        if (match == null) {
          Get.snackbar(
              'Voicemail',
              mailbox.loadFailed
                  ? 'Could not load this voicemail. Try again.'
                  : 'This voicemail is no longer in your mailbox.');
        } else {
          Get.toNamed(Routes.VOICE_MAIL_DETAILS_ROUTE, arguments: match);
        }
        break;
    }
  }
}
