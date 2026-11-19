import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:get/get.dart';
import 'package:itp_voice/routes.dart';
import 'package:itp_voice/services/sip_settings.dart';
import 'package:sip_ua/sip_ua.dart';

void _log(String m) {
  // ignore: avoid_print
  print('[ActiveCall] $m');
}

/// The call in progress, for every kind of call (outbound, in-app incoming,
/// woken by a push), independent of which screen is showing.
///
/// Before this, the call's state (mute, speaker, streams, timer) lived in the
/// call screen's controller, which GetX disposes when the screen is popped:
/// Android Back left the call running with its mic stream disposed and no way
/// back to it. Now the state lives here, the call screen only shows it, a bar
/// on every screen leads back, and on Android an ongoing-call notification
/// (foreground service, phoneCall type) does the same from anywhere.
class ActiveCallService with WidgetsBindingObserver implements SipUaHelperListener {
  ActiveCallService._();
  static final ActiveCallService instance = ActiveCallService._();

  static const MethodChannel _channel = MethodChannel('voice360/app_wake');

  final Rxn<Call> call = Rxn<Call>();
  final Rx<CallStateEnum> state = CallStateEnum.NONE.obs;
  final RxString peerName = ''.obs;
  final RxString peerNumber = ''.obs;
  final RxBool muted = false.obs;
  final RxBool speaker = false.obs;
  final RxBool hold = false.obs;
  final RxString elapsed = ''.obs;
  final RxString currentRoute = ''.obs;
  DateTime? connectedAt;

  MediaStream? localStream;
  MediaStream? remoteStream;

  Timer? _ticker;
  bool _initialized = false;
  bool _notifShown = false;

  SIPUAHelper get helper => SipHolder.helper;

  bool get hasCall => call.value != null;
  bool get isIncomingRinging =>
      call.value?.direction == Direction.incoming && !_connectedStates.contains(state.value);
  bool get isConnected => _connectedStates.contains(state.value);

  static const _connectedStates = {
    CallStateEnum.ACCEPTED,
    CallStateEnum.CONFIRMED,
    CallStateEnum.STREAM,
    CallStateEnum.HOLD,
    CallStateEnum.UNHOLD,
    CallStateEnum.MUTED,
    CallStateEnum.UNMUTED,
  };

  /// Show the "On call" bar: a call exists and the call screen is not on top.
  bool get barVisible => hasCall && currentRoute.value != Routes.CALL_SCREEN_ROUTE;

  void init() {
    if (_initialized) return;
    _initialized = true;
    helper.addSipUaHelperListener(this);
    WidgetsBinding.instance.addObserver(this);
  }

  // ─────────────────────────── SIP events ───────────────────────────

  @override
  void callStateChanged(Call c, CallState s) {
    final current = call.value;
    switch (s.state) {
      case CallStateEnum.CALL_INITIATION:
        if (current == null || _ended(current)) _start(c);
        return;
      case CallStateEnum.STREAM:
        if (current?.id != c.id) return;
        final stream = s.stream;
        if (stream == null) return;
        if (s.originator == Originator.remote) {
          remoteStream = stream;
          _applySpeaker();
        } else {
          for (final t in stream.getAudioTracks()) {
            t.enabled = !muted.value;
          }
          localStream = stream;
        }
        return;
      case CallStateEnum.MUTED:
        if (current?.id == c.id && (s.audio ?? false)) muted.value = true;
        _pushNotification();
        return;
      case CallStateEnum.UNMUTED:
        if (current?.id == c.id && (s.audio ?? false)) muted.value = false;
        _pushNotification();
        return;
      case CallStateEnum.HOLD:
      case CallStateEnum.UNHOLD:
        if (current?.id == c.id) hold.value = s.state == CallStateEnum.HOLD;
        return;
      case CallStateEnum.ENDED:
      case CallStateEnum.FAILED:
        if (current?.id == c.id) _clear();
        return;
      default:
        if (current?.id != c.id) return;
        state.value = s.state;
        if ((s.state == CallStateEnum.ACCEPTED || s.state == CallStateEnum.CONFIRMED) &&
            connectedAt == null) {
          connectedAt = DateTime.now();
          _startTicker();
        }
        _pushNotification();
    }
  }

  bool _ended(Call c) => c.state == CallStateEnum.ENDED || c.state == CallStateEnum.FAILED;

  void _start(Call c) {
    call.value = c;
    state.value = CallStateEnum.CALL_INITIATION;
    connectedAt = null;
    elapsed.value = '';
    muted.value = false;
    speaker.value = false;
    hold.value = false;
    localStream = null;
    remoteStream = null;
    final (name, number) = _peer(c);
    peerName.value = name;
    peerNumber.value = number;
    _log('call ${c.id} ${c.direction == Direction.incoming ? 'from' : 'to'} $number');
    // An incoming call that is still ringing is shown by the call screen or
    // the system call UI; the ongoing notification starts once it is answered.
    if (c.direction != Direction.incoming) _pushNotification();
  }

  void _clear() {
    _log('call ${call.value?.id} ended');
    call.value = null;
    state.value = CallStateEnum.NONE;
    connectedAt = null;
    elapsed.value = '';
    _ticker?.cancel();
    _ticker = null;
    try {
      localStream?.getTracks().forEach((t) => t.stop());
      localStream?.dispose();
    } catch (_) {}
    localStream = null;
    remoteStream = null;
    muted.value = false;
    speaker.value = false;
    if (_notifShown) {
      _notifShown = false;
      _channel.invokeMethod('callEnded').catchError((Object _) => null);
    }
  }

  void _startTicker() {
    _ticker?.cancel();
    void tick() {
      final at = connectedAt;
      if (at == null) return;
      final d = DateTime.now().difference(at);
      final h = d.inHours;
      final mm = d.inMinutes.remainder(60).toString().padLeft(2, '0');
      final ss = d.inSeconds.remainder(60).toString().padLeft(2, '0');
      elapsed.value = h > 0 ? '$h:$mm:$ss' : '$mm:$ss';
    }

    tick();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) => tick());
  }

  static (String, String) _peer(Call c) {
    String name = '';
    String number = '';
    try {
      name = c.remote_display_name ?? '';
      number = c.remote_identity ?? '';
    } catch (_) {}
    if (name.isEmpty) name = number.isEmpty ? 'Unknown' : number;
    return (name, number);
  }

  // ─────────────────────────── controls ───────────────────────────

  void setMuted(bool on) {
    final c = call.value;
    if (c == null) return;
    muted.value = on;
    try {
      on ? c.mute(true, false) : c.unmute(true, false);
    } catch (e) {
      _log('mute failed: $e');
    }
    _pushNotification();
  }

  void toggleMute() => setMuted(!muted.value);

  void setSpeaker(bool on) {
    speaker.value = on;
    _applySpeaker();
    _pushNotification();
  }

  void toggleSpeaker() => setSpeaker(!speaker.value);

  void _applySpeaker() {
    if (kIsWeb) return;
    try {
      final tracks = localStream?.getAudioTracks() ?? remoteStream?.getAudioTracks() ?? const [];
      if (tracks.isNotEmpty) {
        tracks.first.enableSpeakerphone(speaker.value);
      } else {
        Helper.setSpeakerphoneOn(speaker.value);
      }
    } catch (e) {
      _log('speaker failed: $e');
    }
  }

  void hangup() {
    final c = call.value;
    if (c == null) return;
    try {
      c.hangup();
    } catch (e) {
      _log('hangup failed: $e');
      _clear();
    }
  }

  /// Bring the in-call screen back (bar tap, notification tap, iOS return).
  void openCallScreen() {
    final c = call.value;
    if (c == null) return;
    if (Get.key.currentState == null) return;
    if (Get.currentRoute == Routes.CALL_SCREEN_ROUTE) return;
    // The call screen needs the home screen's controllers below it.
    if (Get.currentRoute == Routes.LOGIN_SCREEN_ROUTE) return;
    try {
      Get.toNamed(Routes.CALL_SCREEN_ROUTE, arguments: c);
    } catch (e) {
      _log('could not open the call screen: $e');
    }
  }

  /// Native → Dart (notification actions and taps), routed by CallWakeService.
  void onNativeAction(String action) {
    switch (action) {
      case 'open':
        openCallScreen();
        break;
      case 'mute':
        toggleMute();
        break;
      case 'speaker':
        toggleSpeaker();
        break;
      case 'hangup':
        hangup();
        break;
    }
  }

  // ─────────────── Android ongoing-call notification ───────────────

  void _pushNotification() {
    if (!Platform.isAndroid) return;
    final c = call.value;
    if (c == null) return;
    if (c.direction == Direction.incoming && !isConnected) return;
    _notifShown = true;
    _channel.invokeMethod('callOngoing', {
      'name': peerName.value,
      'number': peerNumber.value,
      'connected_at_ms': connectedAt?.millisecondsSinceEpoch ?? 0,
      'muted': muted.value,
      'speaker': speaker.value,
      'status': isConnected ? 'On call' : 'Calling',
    }).catchError((Object e) {
      _log('ongoing notification failed: $e');
      return null;
    });
  }

  // ─────────────────────────── lifecycle ───────────────────────────

  @override
  void didChangeAppLifecycleState(AppLifecycleState s) {
    // iOS: the green call pill, the status bar and CallKit's app button all
    // just bring the app forward; show the call when that happens.
    if (s == AppLifecycleState.resumed && Platform.isIOS && hasCall) {
      Future.delayed(const Duration(milliseconds: 300), openCallScreen);
    }
  }

  @override
  void onNewMessage(SIPMessageRequest msg) {}

  @override
  void onNewNotify(Notify ntf) {}

  @override
  void onNewReinvite(ReInvite event) {}

  @override
  void registrationStateChanged(RegistrationState state) {}

  @override
  void transportStateChanged(TransportState state) {}
}
