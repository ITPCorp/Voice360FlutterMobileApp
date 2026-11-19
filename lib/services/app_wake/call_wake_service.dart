import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_callkit_incoming/entities/call_event.dart';
import 'package:flutter_callkit_incoming/flutter_callkit_incoming.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart' as rtc;
import 'package:get/get.dart';
import 'package:itp_voice/controllers/base_screen_controller.dart';
import 'package:itp_voice/models/get_devices_reponse_model/devices.dart';
import 'package:itp_voice/routes.dart';
import 'package:itp_voice/services/app_wake/wake_call.dart';
import 'package:itp_voice/services/sip_settings.dart';
import 'package:itp_voice/storage_keys.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sip_ua/sip_ua.dart';

void _log(String m) {
  // ignore: avoid_print
  print('[AppWake] $m');
}

/// Inbound calls while the app is backgrounded or killed ("app-wake").
///
/// Native code receives the push (iOS PushKit in AppDelegate, Android FCM in
/// AppWakeMessagingService), shows the system call UI at once (CallKit /
/// self-managed Telecom + full-screen notification) and hands the push to this
/// service over the `voice360/app_wake` channel. This service then starts the
/// SIP UA with no screen, REGISTERs over WSS, matches the INVITE the dialplan
/// sends to the call on screen, and answers or rejects it according to what
/// the user tapped, including taps that come before the INVITE.
///
/// It also owns the UA lifecycle: the app unregisters when it goes to the
/// background with no call, so the dialplan sees it as not registered and
/// pushes instead of INVITEing a socket the OS has frozen.
class CallWakeService with WidgetsBindingObserver implements SipUaHelperListener {
  CallWakeService._();
  static final CallWakeService instance = CallWakeService._();

  static const MethodChannel _channel = MethodChannel('voice360/app_wake');
  static const _timingsKey = 'app_wake_timings';
  static const _permsAskedKey = 'app_wake_perms_asked_v1';

  /// How long a woken call may wait for its INVITE before the UI is dropped.
  /// The dialplan never waits longer than the user's ring time (+2 s).
  static const inviteTimeout = Duration(seconds: 75);

  SIPUAHelper get helper => SipHolder.helper;

  final Map<String, WakeCall> _calls = {}; // by call_id
  /// call_ids finished here (answered+hung up, declined, cancelled). A later
  /// cancel push for one of them is ignored (BUGS.md F4).
  final List<String> _finished = [];
  final Map<String, Timer> _inviteTimers = {};
  final Set<String> _activeSip = {}; // sip_ua call ids not ended yet

  bool _initialized = false;
  bool _uaRunning = false;
  bool _foreground = true;
  Timer? _quietTimer;
  Call? _pendingCallScreen;
  String? _voipToken;
  final _voipTokenCtl = StreamController<String>.broadcast();

  /// iOS PushKit token (hex), null on Android or before PushKit answered.
  String? get voipToken => _voipToken;
  Stream<String> get voipTokenChanges => _voipTokenCtl.stream;

  /// Last wake timings, newest first (debug screen).
  final RxList<String> recentTimings = <String>[].obs;

  bool get hasWakeCalls => _calls.isNotEmpty;

  final Completer<void> _readyDone = Completer<void>();
  Completer<void>? _wakeRegistered;

  /// Startup work that is not needed to take a call (time zones, caches,
  /// auto-login API calls) awaits this. When the app was started by a call
  /// push it holds until the SIP REGISTER answered (max [max]), so the Dart
  /// isolate is free for the REGISTER on a cold wake. Otherwise it returns as
  /// soon as native said whether a push is waiting (max ~0.5 s).
  Future<void> startupGate({Duration max = const Duration(seconds: 4)}) async {
    try {
      await _readyDone.future.timeout(const Duration(milliseconds: 600));
    } catch (_) {}
    final w = _wakeRegistered;
    if (w == null || w.isCompleted) return;
    final t0 = _now();
    try {
      await w.future.timeout(max);
    } catch (_) {}
    _log('startup work held ${_now() - t0} ms for the wake REGISTER');
  }

  // ───────────────────────────────── init ─────────────────────────────────

  /// Called from main() before runApp. Safe to call more than once.
  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;
    WidgetsBinding.instance.addObserver(this);
    final ls = WidgetsBinding.instance.lifecycleState;
    _foreground = ls == null || ls == AppLifecycleState.resumed;
    helper.addSipUaHelperListener(this);
    _channel.setMethodCallHandler(_onNativeCall);
    if (Platform.isAndroid) {
      FlutterCallkitIncoming.onEvent.listen(_onCallkitEvent, onError: (e) {
        _log('callkit event error $e');
      });
    }
    unawaited(_loadTimings());
    await _ready();
    if (!_readyDone.isCompleted) _readyDone.complete();
  }

  /// Tell native Dart is listening and take what it queued. On Android the
  /// channel can be bound a moment after this engine starts (audio_service may
  /// create the engine), so a missing bridge is retried for a few seconds.
  Future<void> _ready([int attempt = 0]) async {
    try {
      final res = await _channel.invokeMethod<dynamic>('ready');
      if (res is Map) {
        final t = res['voipToken'];
        if (t is String && t.isNotEmpty) _setVoipToken(t);
        final events = res['events'];
        if (events is List) {
          _log('native had ${events.length} queued event(s)');
          for (final e in events) {
            if (e is Map) _onNativeEvent(e);
          }
        }
      }
    } on MissingPluginException {
      if (attempt < 10 && (Platform.isAndroid || Platform.isIOS)) {
        await Future.delayed(const Duration(seconds: 1));
        return _ready(attempt + 1);
      }
      _log('no native app-wake bridge on this platform');
    } catch (e) {
      _log('ready failed: $e');
    }
  }

  Future<dynamic> _onNativeCall(MethodCall call) async {
    if (call.method == 'onEvent' && call.arguments is Map) {
      _onNativeEvent(call.arguments as Map);
    }
    return null;
  }

  void _onNativeEvent(Map e) {
    final event = (e['event'] ?? '').toString();
    switch (event) {
      case 'push':
        final p = WakePush.fromMap(e);
        if (p == null) {
          _log('ignored push $e');
          return;
        }
        if (p.isRing) {
          _onRing(p, cold: e['cold_start']?.toString() == '1');
        } else {
          _onCancel(p);
        }
        break;
      case 'voipToken':
        _setVoipToken((e['token'] ?? '').toString());
        break;
      case 'answer':
        _onNativeAnswer((e['uuid'] ?? '').toString());
        break;
      case 'end':
        _onNativeEnd((e['uuid'] ?? '').toString(), reason: 'user');
        break;
      case 'mute':
        _onNativeMute((e['uuid'] ?? '').toString(), e['muted']?.toString() == '1');
        break;
      case 'audio':
        _log('CallKit audio session ${e['active'] == '1' ? 'active' : 'inactive'}');
        break;
      default:
        _log('unknown native event $event');
    }
  }

  void _setVoipToken(String t) {
    if (t.isEmpty || t == _voipToken) return;
    _voipToken = t;
    _log('VoIP token ${t.substring(0, t.length < 8 ? t.length : 8)}…');
    _voipTokenCtl.add(t);
  }

  /// iOS: wait briefly for PushKit to hand over a token (login runs right after
  /// launch on a fresh install).
  Future<String?> waitForVoipToken({Duration timeout = const Duration(seconds: 3)}) async {
    if (!Platform.isIOS) return null;
    if (_voipToken != null) return _voipToken;
    try {
      final t = await _channel.invokeMethod<String>('getVoipToken');
      if (t != null && t.isNotEmpty) _setVoipToken(t);
    } catch (_) {}
    if (_voipToken != null) return _voipToken;
    try {
      return await voipTokenChanges.first.timeout(timeout);
    } catch (_) {
      return _voipToken;
    }
  }

  // ─────────────────────────────── pushes ────────────────────────────────

  void _onRing(WakePush p, {bool cold = false}) {
    if (_finished.contains(p.callId)) {
      _log('ring for finished call ${p.callId}, ignored');
      return;
    }
    if (_calls.containsKey(p.callId)) {
      _log('duplicate ring ${p.callId}');
      return;
    }
    final c = WakeCall(p);
    c.t.dartSeen = _now();
    c.t.coldStart = cold;
    _calls[p.callId] = c;
    _log('ring ${p.callId} from ${p.callerNumber} '
        '(push ${p.sentAtMs == null ? '?' : p.receivedAtMs - p.sentAtMs!} ms in transit, '
        'dart +${c.t.dartSeen! - p.receivedAtMs} ms${cold ? ', cold start' : ''})');
    _inviteTimers[p.callId] = Timer(inviteTimeout, () => _inviteTimedOut(p.callId));
    if (!helper.registered && (_wakeRegistered == null || _wakeRegistered!.isCompleted)) {
      _wakeRegistered = Completer<void>();
    }
    unawaited(_ensureRegistered(c));
  }

  void _onCancel(WakePush p) {
    final c = _calls[p.callId];
    if (c == null || c.state == WakeState.ended) {
      // F4: the app already ended this call (declined, or it never got here).
      _log('cancel for ${p.callId}: not active here, ignored');
      return;
    }
    if (c.state == WakeState.answered || c.state == WakeState.answering) {
      _log('cancel for ${p.callId} after answer, ignored');
      return;
    }
    c.nativeEnded = true; // native already took the call UI down
    if (c.inviteId != null) {
      // Asterisk sends a SIP CANCEL as well; that ends it through sip_ua.
      _log('cancel push for ${p.callId}, waiting for the SIP CANCEL');
      return;
    }
    _finish(
        c,
        c.declined
            ? 'declined before INVITE'
            : 'cancelled before INVITE${c.accepted ? ' (user had tapped Answer)' : ''}');
  }

  void _inviteTimedOut(String callId) {
    final c = _calls[callId];
    if (c == null || c.inviteId != null) return;
    _log('no INVITE for $callId after ${inviteTimeout.inSeconds} s');
    _endNative(c, 'failed');
    _finish(c, 'no INVITE');
  }

  // ───────────────────────────── SIP UA ──────────────────────────────────

  /// Start the UA (if it is not running) with the stored app_phone device.
  /// Used by the wake path and by BaseScreenController.
  Future<bool> startUa() async {
    if (_uaRunning && (helper.connected || helper.connecting)) {
      return true;
    }
    final prefs = await SharedPreferences.getInstance();
    final realm = prefs.getString(StorageKeys.REALM);
    final raw = prefs.getString(StorageKeys.DEVICE);
    Devices? device;
    try {
      device = raw == null ? null : Devices.fromJson(raw);
    } catch (_) {}
    final token = prefs.getString(StorageKeys.REFRESH_TOKEN);
    if (realm == null || realm.isEmpty || device?.sipUsername == null ||
        device?.sipPassword == null || token == null || token.isEmpty) {
      _log('no stored session/device, cannot start the SIP UA');
      return false;
    }
    _uaRunning = true;
    try {
      await helper.start(buildUaSettings(
          realm: realm,
          username: device!.sipUsername!,
          password: device.sipPassword!));
      return true;
    } catch (e) {
      _log('UA start failed: $e');
      _uaRunning = false;
      return false;
    }
  }

  /// Unregister and stop the UA.
  Future<void> stopUa(String why) async {
    if (!_uaRunning) return;
    _log('stopping UA: $why');
    _uaRunning = false;
    try {
      if (helper.registered) {
        await helper.unregister(true).timeout(const Duration(seconds: 3));
      }
    } catch (e) {
      _log('unregister failed: $e');
    }
    try {
      helper.stop();
    } catch (_) {}
  }

  Future<void> _ensureRegistered(WakeCall c) async {
    if (helper.registered) {
      c.t.alreadyRegistered = true;
      c.t.registered = _now();
      _log('UA already registered for ${c.callId}');
      return;
    }
    if (_uaRunning && (helper.connected || helper.connecting)) {
      _log('UA already starting, waiting for REGISTER 200');
      return;
    }
    if (!_micReadyForWake()) {
      _log('mic permission not granted, the call can ring but cannot carry audio');
    }
    c.t.uaStart = _now();
    final ok = await startUa();
    if (!ok) {
      _endNative(c, 'failed');
      _finish(c, 'not signed in');
    }
  }

  bool _micGranted = true;
  bool _micReadyForWake() => _micGranted;

  // ─────────────────────── SipUaHelperListener ─────────────────────────

  @override
  void transportStateChanged(TransportState state) {
    if (state.state == TransportStateEnum.CONNECTED) {
      final now = _now();
      for (final c in _calls.values) {
        c.t.wsConnected ??= now;
      }
    }
  }

  @override
  void registrationStateChanged(RegistrationState state) {
    final now = _now();
    if (state.state != RegistrationStateEnum.NONE) {
      final w = _wakeRegistered;
      if (w != null && !w.isCompleted) w.complete();
    }
    if (state.state == RegistrationStateEnum.REGISTERED) {
      for (final c in _calls.values) {
        if (c.t.registered == null) {
          c.t.registered = now;
          _log('REGISTER 200 for ${c.callId} at +${now - c.t.pushReceived} ms');
        }
      }
    } else if (state.state == RegistrationStateEnum.REGISTRATION_FAILED) {
      _log('REGISTER failed: ${state.cause}');
    }
  }

  @override
  void callStateChanged(Call call, CallState state) {
    final id = call.id;
    if (id == null) return;
    switch (state.state) {
      case CallStateEnum.CALL_INITIATION:
        _activeSip.add(id);
        if (call.direction == Direction.incoming) claim(call);
        return;
      case CallStateEnum.ENDED:
      case CallStateEnum.FAILED:
        _activeSip.remove(id);
        final c = _byInvite(id);
        if (c != null) {
          final remoteCancel = state.state == CallStateEnum.FAILED &&
              (state.cause?.cause == 'Canceled' || state.cause?.cause == 'Request Timeout');
          if (c.state == WakeState.answered || c.state == WakeState.answering) {
            _endNative(c, 'ended');
            _finish(c, 'answered, ended');
          } else if (c.declined) {
            _finish(c, 'declined');
          } else {
            if (!c.nativeEnded) _endNative(c, remoteCancel ? 'missed' : 'failed');
            _finish(c, remoteCancel ? 'missed (SIP CANCEL)' : 'failed ${state.cause}');
          }
        }
        _maybeGoQuiet();
        return;
      case CallStateEnum.ACCEPTED:
      case CallStateEnum.CONFIRMED:
        final c = _byInvite(id);
        if (c != null && c.state != WakeState.answered) {
          c.state = WakeState.answered;
          c.t.answered ??= _now();
          _log('answered ${c.callId}: ${c.t.summary()}');
          _native('connected', {'uuid': c.uuid, 'call_id': c.callId});
        }
        return;
      default:
        return;
    }
  }

  @override
  void onNewMessage(SIPMessageRequest msg) {}

  @override
  void onNewNotify(Notify ntf) {}

  @override
  void onNewReinvite(ReInvite event) {}

  /// If [call] is the INVITE for a woken call, take it (the native UI is the
  /// ringing screen) and return the wake call. BaseScreenController calls this
  /// first and skips its own incoming-call screen when it returns non-null.
  WakeCall? claim(Call call) {
    final id = call.id;
    if (id == null || call.direction != Direction.incoming) return null;
    final existing = _byInvite(id);
    if (existing != null) return existing;
    dynamic req;
    try {
      req = call.session.request;
    } catch (_) {}
    String? header(String name) {
      try {
        final v = req?.getHeader(name);
        return v?.toString();
      } catch (_) {
        return null;
      }
    }

    String? from;
    try {
      from = call.remote_identity;
    } catch (_) {}
    final m = InviteMatcher.match(header, from, _calls.values);
    if (m == null) {
      if (_calls.isNotEmpty) {
        _log('INVITE $id did not match any woken call '
            '(X-UniqueID=${header('X-UniqueID')}, X-OriginalUniqueID=${header('X-OriginalUniqueID')})');
      }
      return null;
    }
    final c = m.$1;
    c.inviteId = id;
    c.t.invite = _now();
    c.t.matchedBy = m.$2;
    _inviteTimers.remove(c.callId)?.cancel();
    _log('INVITE for ${c.callId} matched by ${m.$2} at +${c.t.invite! - c.t.pushReceived} ms');
    if (c.declined) {
      _reject(call);
    } else if (c.accepted) {
      unawaited(_answer(c, call));
    }
    return c;
  }

  WakeCall? _byInvite(String sipId) {
    for (final c in _calls.values) {
      if (c.inviteId == sipId) return c;
    }
    return null;
  }

  WakeCall? _byUuid(String uuid) {
    for (final c in _calls.values) {
      if (c.uuid.toLowerCase() == uuid.toLowerCase()) return c;
    }
    return null;
  }

  // ─────────────────────── native UI actions ────────────────────────────

  void _onNativeAnswer(String uuid) {
    final c = _byUuid(uuid);
    if (c == null) {
      _log('Answer for unknown call $uuid');
      return;
    }
    if (c.accepted) return;
    c.accepted = true;
    c.t.answerTap = _now();
    final call = c.inviteId == null ? null : helper.findCall(c.inviteId!);
    if (call == null) {
      _log('Answer tapped for ${c.callId} before the INVITE; answering when it lands');
    } else {
      unawaited(_answer(c, call));
    }
  }

  void _onNativeEnd(String uuid, {required String reason}) {
    final c = _byUuid(uuid);
    if (c == null) return;
    c.nativeEnded = true;
    final call = c.inviteId == null ? null : helper.findCall(c.inviteId!);
    if (c.state == WakeState.answered || c.state == WakeState.answering) {
      _log('hang up ${c.callId} from the system call UI');
      try {
        call?.hangup();
      } catch (_) {}
      if (call == null) _finish(c, 'hung up before INVITE');
      return;
    }
    if (c.state == WakeState.ended) return;
    c.declined = true;
    _remember(c.callId);
    // Native must not turn the dialplan's later cancel push into a
    // "missed call" for a call the user declined.
    _native('markEnded', {'call_id': c.callId, 'uuid': c.uuid});
    if (call != null) {
      _reject(call);
    } else {
      // Keep the call until its INVITE arrives (reject it then) or the
      // dialplan gives up (cancel push / timeout).
      _log('declined ${c.callId} before the INVITE');
    }
  }

  void _onNativeMute(String uuid, bool muted) {
    final c = _byUuid(uuid);
    final call = c?.inviteId == null ? null : helper.findCall(c!.inviteId!);
    if (call == null) return;
    try {
      muted ? call.mute(true, false) : call.unmute(true, false);
    } catch (_) {}
  }

  void _onCallkitEvent(CallEvent? e) {
    switch (e) {
      case CallEventActionCallAccept(:final callKitParams):
        _onNativeAnswer(callKitParams.id);
      case CallEventActionCallDecline(:final callKitParams):
        _onNativeEnd(callKitParams.id, reason: 'decline');
      case CallEventActionCallEnded(:final callKitParams):
        _onNativeEnd(callKitParams.id, reason: 'ended');
      case CallEventActionCallTimeout(:final id):
        _onNativeEnd(id, reason: 'timeout');
      case CallEventActionCallToggleMute(:final id, :final isMuted):
        _onNativeMute(id, isMuted);
      default:
        break;
    }
  }

  Future<void> _answer(WakeCall c, Call call) async {
    if (c.state == WakeState.answering || c.state == WakeState.answered) return;
    c.state = WakeState.answering;
    try {
      final stream = await rtc.navigator.mediaDevices
          .getUserMedia(<String, dynamic>{'audio': true, 'video': false});
      call.answer(helper.buildCallOptions(true), mediaStream: stream);
      _log('answering ${c.callId}');
      _showCallScreen(call);
    } catch (e) {
      _log('answer failed for ${c.callId}: $e');
      c.state = WakeState.ringing;
      try {
        call.hangup({'status_code': 500});
      } catch (_) {}
      _endNative(c, 'failed');
    }
  }

  void _reject(Call call) {
    try {
      call.hangup({'status_code': 603});
      _log('rejected INVITE ${call.id} with 603');
    } catch (e) {
      _log('reject failed: $e');
    }
  }

  // ─────────────────────────── bookkeeping ──────────────────────────────

  void _finish(WakeCall c, String outcome) {
    if (c.state == WakeState.ended && !_calls.containsKey(c.callId)) return;
    c.state = WakeState.ended;
    c.t.ended = _now();
    c.t.outcome = outcome;
    _inviteTimers.remove(c.callId)?.cancel();
    _calls.remove(c.callId);
    _remember(c.callId);
    _native('markEnded', {'call_id': c.callId, 'uuid': c.uuid});
    _log('${c.callId} done: ${c.t.summary()}');
    unawaited(_saveTiming(c));
    _maybeGoQuiet();
  }

  void _remember(String callId) {
    if (_finished.contains(callId)) return;
    _finished.add(callId);
    if (_finished.length > 50) _finished.removeAt(0);
  }

  void _endNative(WakeCall c, String reason) {
    if (c.nativeEnded) return;
    c.nativeEnded = true;
    _native('endCall', {'uuid': c.uuid, 'call_id': c.callId, 'reason': reason});
  }

  void _native(String method, Map<String, dynamic> args) {
    _channel.invokeMethod(method, args).catchError((Object e) {
      _log('$method failed: $e');
      return null;
    });
  }

  /// True while [sipCallId] belongs to a woken call that was answered on the
  /// system UI (the Flutter call screen then opens as already accepted).
  bool isAnsweredByWake(String? sipCallId) {
    if (sipCallId == null) return false;
    final c = _byInvite(sipCallId);
    return c != null && (c.state == WakeState.answered || c.state == WakeState.answering);
  }

  // ─────────────────────── call screen after answer ──────────────────────

  void _showCallScreen(Call call) {
    _pendingCallScreen = call;
    flushCallScreen();
  }

  /// Open the in-call screen for a call answered on the system UI once the
  /// app has a home screen in front. BaseScreenController.onReady and app
  /// resume call this.
  void flushCallScreen() {
    final call = _pendingCallScreen;
    if (call == null || !_foreground) return;
    // Needs the home screen: the call screen uses its controllers.
    if (Get.key.currentState == null || !Get.isRegistered<BaseScreenController>()) return;
    _pendingCallScreen = null;
    if (call.state == CallStateEnum.ENDED || call.state == CallStateEnum.FAILED) return;
    if (Get.currentRoute == Routes.CALL_SCREEN_ROUTE) return;
    try {
      Get.toNamed(Routes.CALL_SCREEN_ROUTE, arguments: call);
    } catch (e) {
      _log('could not open the call screen: $e');
      _pendingCallScreen = call;
    }
  }

  // ─────────────────────── foreground / background ───────────────────────

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.resumed:
        _foreground = true;
        _quietTimer?.cancel();
        _quietTimer = null;
            if (!_uaRunning && _signedInUi()) {
          unawaited(startUa());
        }
        flushCallScreen();
        break;
      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
      case AppLifecycleState.detached:
        if (_foreground) {
          _foreground = false;
          _maybeGoQuiet();
        }
        break;
      case AppLifecycleState.inactive:
        break;
    }
  }

  /// The home screen exists (signed in, UI built).
  bool _signedInUi() => Get.isRegistered<BaseScreenController>();

  /// In the background with no call: unregister so the next call pushes.
  void _maybeGoQuiet() {
    if (_foreground || !_uaRunning) return;
    if (_calls.isNotEmpty || _activeSip.isNotEmpty) return;
    _quietTimer?.cancel();
    // A short grace so a permission dialog or the full-screen call activity
    // covering the app does not drop the registration.
    _quietTimer = Timer(const Duration(milliseconds: 1500), () async {
      _quietTimer = null;
      if (_foreground || _calls.isNotEmpty || _activeSip.isNotEmpty) return;
      int? bg;
      try {
        bg = await _channel.invokeMethod<int>('beginBackground');
      } catch (_) {}
      await stopUa('app in background, no call');
      if (bg != null) {
        try {
          await _channel.invokeMethod('endBackground', {'id': bg});
        } catch (_) {}
      }
    });
  }

  /// Logout: drop everything.
  Future<void> onLogout() async {
    for (final c in _calls.values.toList()) {
      _endNative(c, 'failed');
      _finish(c, 'logout');
    }
    await stopUa('logout');
  }

  // ───────────────────────────── permissions ─────────────────────────────

  /// Ask once for what a call answered from the lock screen needs: the mic,
  /// and on Android 13/14+ notifications and full-screen intents.
  Future<void> ensureCallPermissions() async {
    try {
      final mic = await Permission.microphone.request();
      _micGranted = mic.isGranted;
    } catch (_) {}
    if (!Platform.isAndroid) return;
    try {
      await FlutterCallkitIncoming.requestNotificationPermission({
        'title': 'Notifications',
        'rationaleMessagePermission':
            'VOICE360 needs notifications to show incoming calls.',
        'postNotificationMessageRequired':
            'Allow notifications in Settings so VOICE360 can ring for calls.',
      });
    } catch (_) {}
    try {
      final prefs = await SharedPreferences.getInstance();
      final can = await FlutterCallkitIncoming.canUseFullScreenIntent();
      if (can == false && prefs.getBool(_permsAskedKey) != true) {
        await prefs.setBool(_permsAskedKey, true);
        await FlutterCallkitIncoming.requestFullIntentPermission();
      }
    } catch (_) {}
  }

  // ─────────────────────────────── timings ───────────────────────────────

  Future<void> _loadTimings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final list = prefs.getStringList(_timingsKey) ?? const [];
      recentTimings.assignAll(list.map((s) {
        try {
          final m = jsonDecode(s) as Map<String, dynamic>;
          return _timingLine(m);
        } catch (_) {
          return s;
        }
      }));
    } catch (_) {}
  }

  Future<void> _saveTiming(WakeCall c) async {
    final m = c.t.toJson(c.callId);
    recentTimings.insert(0, _timingLine(m));
    if (recentTimings.length > 20) recentTimings.removeRange(20, recentTimings.length);
    try {
      final prefs = await SharedPreferences.getInstance();
      final list = prefs.getStringList(_timingsKey) ?? <String>[];
      list.insert(0, jsonEncode(m));
      await prefs.setStringList(_timingsKey, list.take(20).toList());
    } catch (_) {}
  }

  /// Raw JSON rows (newest first) for copying off the phone.
  Future<List<String>> timingRows() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getStringList(_timingsKey) ?? const [];
  }

  static String _timingLine(Map<String, dynamic> m) {
    String f(String k) => m[k] == null ? '-' : '${m[k]}';
    return '${f('at')}  ${f('outcome')}\n'
        'transit ${f('push_transit_ms')} · dart ${f('dart_ms')} · ws ${f('ws_ms')} · '
        'REG200 ${f('register_ms')} · INVITE ${f('invite_ms')} · tap ${f('answer_tap_ms')} · '
        'answered ${f('answered_ms')}${m['cold_start'] == true ? ' · cold' : ''}'
        '${m['matched_by'] == null ? '' : ' · ${m['matched_by']}'}';
  }

  int _now() => DateTime.now().millisecondsSinceEpoch;
}
