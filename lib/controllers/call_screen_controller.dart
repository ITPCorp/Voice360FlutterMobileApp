import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart' as flwebrtc;
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:get/get.dart';
import 'package:itp_voice/routes.dart';
import 'package:itp_voice/services/active_call_service.dart';
import 'package:itp_voice/services/app_wake/call_wake_service.dart';
import 'package:proximity_sensor/proximity_sensor.dart';
import 'package:sip_ua/sip_ua.dart';

import '../widgets/custom_toast.dart';

/// The in-call screen. It only shows and drives [ActiveCallService]: the call
/// and its mute/speaker/hold state, streams and timer live there, so leaving
/// this screen (Android Back, home button) no longer touches the call, and the
/// "On call" bar or the ongoing-call notification bring it back.
class CallScreenController extends GetxController implements SipUaHelperListener {
  final ActiveCallService active = ActiveCallService.instance;

  RxBool showNumpad = false.obs;
  RxBool videoMuted = false.obs;
  RxString? holdOriginator = "".obs;
  RxBool? isIncomingCall = false.obs;
  RxBool? isIncomingCallAccepted = false.obs;
  Rx<CallStateEnum> state = CallStateEnum.NONE.obs;

  RxBool get audioMuted => active.muted;
  RxBool get speakerOn => active.speaker;
  RxBool get hold => active.hold;
  RxString get timeLabel => active.elapsed;

  SIPUAHelper? helper;
  Call? call;

  StreamSubscription? proximityStream;
  RxBool isNear = false.obs;
  static bool _audioServiceReady = false;

  @override
  void onClose() {
    // Deliberately NOT disposing the call's streams: the call goes on after
    // this screen closes. ActiveCallService releases them when the call ends.
    helper?.removeSipUaHelperListener(this);
    proximityStream?.cancel();
    super.onClose();
  }

  @override
  void onInit() async {
    super.onInit();
    final arg = Get.arguments;
    call = arg is Call ? arg : active.call.value;
    helper = Get.find<SIPUAHelper>();
    helper!.addSipUaHelperListener(this);
    if (call != null) {
      // Reopened from the bar / notification: show the call as it is now.
      state.value = active.call.value?.id == call!.id ? active.state.value : call!.state;
      if (call!.direction == Direction.incoming) {
        isIncomingCall!.value = true;
        // Answered on CallKit / the Android call notification (app-wake), or
        // answered earlier on this screen.
        isIncomingCallAccepted!.value =
            CallWakeService.instance.isAnsweredByWake(call!.id) || active.isConnected;
      }
    }
    proximityStream = ProximitySensor.events.listen((event) {
      isNear.value = event > 0;
    });
    if (!_audioServiceReady) {
      _audioServiceReady = true;
      try {
        await AudioService.init(
          builder: () => MyAudioHandler(controller: this),
          config: const AudioServiceConfig(
            androidNotificationChannelId: 'com.ryanheise.myapp.channel.audio',
            androidNotificationIcon: 'drawable/ic_stat_voice360',
            androidNotificationChannelName: 'Audio playback',
            androidNotificationOngoing: true,
          ),
        );
      } catch (e) {
        // ignore: avoid_print
        print('AudioService.init: $e');
      }
    }
  }

  @override
  void callStateChanged(Call c, CallState callState) {
    if (call == null || c.id != call!.id) return;
    switch (callState.state) {
      case CallStateEnum.HOLD:
      case CallStateEnum.UNHOLD:
        holdOriginator!.value = callState.originator?.toString() ?? '';
        return;
      case CallStateEnum.MUTED:
      case CallStateEnum.UNMUTED:
      case CallStateEnum.STREAM:
        return;
      case CallStateEnum.ENDED:
      case CallStateEnum.FAILED:
        state.value = callState.state;
        _closeIfShowing();
        return;
      case CallStateEnum.ACCEPTED:
        state.value = CallStateEnum.ACCEPTED;
        isIncomingCallAccepted!.value = true;
        return;
      case CallStateEnum.CONFIRMED:
        state.value = CallStateEnum.CONFIRMED;
        // Audio kickstart: on this Android stack the local mic track comes
        // up with `track.enabled = false` and the only way to flip it to
        // true is via sip_ua's _toggleMuteAudio(false). Cycle it once so audio
        // flows from the start (unless the user already muted).
        Future.microtask(() {
          if (call == null || active.muted.value) return;
          try {
            call!.mute(true, false);
            call!.unmute(true, false);
            active.muted.value = false;
          } catch (e) {
            // ignore: avoid_print
            print('Audio kickstart failed: $e');
          }
        });
        return;
      default:
        state.value = callState.state;
    }
  }

  /// Leave the call screen when its call ends, but only if it is the screen
  /// on top: the user may be elsewhere in the app (the old code popped
  /// whatever screen was showing).
  void _closeIfShowing() {
    if (Get.currentRoute == Routes.CALL_SCREEN_ROUTE) Get.back();
  }

  @override
  void onNewMessage(SIPMessageRequest msg) {}

  @override
  void registrationStateChanged(RegistrationState state) {}

  @override
  void transportStateChanged(TransportState state) {}

  void handleDtmf(String tone) {
    call?.sendDTMF(tone);
  }

  void handleHangup({bool goBack = false}) {
    try {
      call?.hangup();
    } catch (e) {
      // ignore: avoid_print
      print(e.toString());
    }
    if (goBack) _closeIfShowing();
  }

  void toggleSpeaker() => active.toggleSpeaker();

  void turnOffSpeaker() => active.setSpeaker(false);

  void handleAccept() async {
    if (call == null) return;
    bool remoteHasVideo = call!.remote_has_video;
    final mediaConstraints = <String, dynamic>{'audio': true, 'video': remoteHasVideo};
    MediaStream mediaStream;

    if (kIsWeb && remoteHasVideo) {
      mediaStream = await flwebrtc.navigator.mediaDevices.getDisplayMedia(mediaConstraints);
      mediaConstraints['video'] = false;
      MediaStream userStream = await flwebrtc.navigator.mediaDevices.getUserMedia(mediaConstraints);
      mediaStream.addTrack(userStream.getAudioTracks()[0], addToNative: true);
    } else {
      mediaConstraints['video'] = remoteHasVideo;
      mediaStream = await flwebrtc.navigator.mediaDevices.getUserMedia(mediaConstraints);
    }

    call!.answer(helper!.buildCallOptions(!remoteHasVideo), mediaStream: mediaStream);
    isIncomingCallAccepted!.value = true;
  }

  void switchCamera() {
    final s = active.localStream;
    if (s != null && s.getVideoTracks().isNotEmpty) {
      Helper.switchCamera(s.getVideoTracks()[0]);
    }
  }

  void muteAudio() => active.toggleMute();

  void muteVideo() {
    final next = !videoMuted.value;
    videoMuted.value = next;
    if (next) {
      call?.mute(false, true);
    } else {
      call?.unmute(false, true);
    }
  }

  void handleHold() {
    if (hold.value) {
      call?.unhold();
    } else {
      call?.hold();
    }
  }

  callStatus() {
    if (isIncomingCall!.value && !isIncomingCallAccepted!.value) {
      return "Incoming Call";
    }
    if (state.value == CallStateEnum.CALL_INITIATION) {
      return "Calling";
    }
    if (state.value == CallStateEnum.CONFIRMED) {
      return "Ringing";
    }
  }

  @override
  void onNewNotify(Object ntf) {}

  @override
  void onNewReinvite(ReInvite event) {}
}

class MyAudioHandler extends BaseAudioHandler with QueueHandler, SeekHandler {
  // Bound to the first call screen's controller; media buttons act on the
  // active call through ActiveCallService instead.
  final CallScreenController controller;
  MyAudioHandler({required this.controller});

  @override
  Future<void> play() async {
    final active = ActiveCallService.instance;
    final c = active.call.value;
    if (c != null && c.direction == Direction.incoming && !active.isConnected) {
      try {
        if (Get.isRegistered<CallScreenController>()) {
          Get.find<CallScreenController>().handleAccept();
        }
      } catch (e) {
        CustomToast.showToast(e.toString(), true);
      }
    }
  }

  @override
  Future<void> stop() async {
    try {
      ActiveCallService.instance.hangup();
    } catch (e) {
      CustomToast.showToast(e.toString(), true);
    }
  }
}
