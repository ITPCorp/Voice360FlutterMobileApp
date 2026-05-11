import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart' as flwebrtc;
import 'package:get/get.dart';
import 'package:get/get_state_manager/src/simple/get_controllers.dart';
import 'package:itp_voice/routes.dart';
import 'package:proximity_sensor/proximity_sensor.dart';
import 'package:sip_ua/sip_ua.dart';
import 'package:just_audio/just_audio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import '../main.dart';
import '../widgets/custom_toast.dart';

class CallScreenController extends GetxController
    implements SipUaHelperListener {
  RxBool showNumpad = false.obs;
  RxBool audioMuted = false.obs;
  RxBool videoMuted = false.obs;
  RxBool speakerOn = false.obs;
  RxBool hold = false.obs;
  RxString? holdOriginator = "".obs;
  RxBool? isIncomingCall = false.obs;
  RxBool? isIncomingCallAccepted = false.obs;
  Rx<CallStateEnum> state = CallStateEnum.NONE.obs;
  RxString timeLabel = ''.obs;
  Timer? timer;
  RTCVideoRenderer? localRenderer = RTCVideoRenderer();
  RTCVideoRenderer? remoteRenderer = RTCVideoRenderer();
  MediaStream? localStream;
  MediaStream? remoteStream;
  bool get voiceonly =>
      (localStream == null || localStream!.getVideoTracks().isEmpty) &&
      (remoteStream == null || remoteStream!.getVideoTracks().isEmpty);
  SIPUAHelper? helper;
  Call? call;

  late StreamSubscription proximityStream;
  RxBool isNear = false.obs;

  @override
  void onClose() {
    // TODO: implement onClose
    localStream?.dispose();
    timer?.cancel();
    super.onClose();
  }

  @override
  void onInit() async {
    // TODO: implement onInit
    call = Get.arguments;
    if (call!.direction == "INCOMING") {
      isIncomingCall!.value = true;
      isIncomingCallAccepted!.value = false;
    }
    helper = Get.find<SIPUAHelper>();
    helper!.addSipUaHelperListener(this);
    // startTimer();
    proximityStream = ProximitySensor.events.listen((event) {
      print('Proximity event: $event');
      isNear.value = (event > 0) ? true : false;
    });
    await AudioService.init(
      builder: () => MyAudioHandler(controller: this),
      config: const AudioServiceConfig(
        androidNotificationChannelId: 'com.ryanheise.myapp.channel.audio',
        androidNotificationChannelName: 'Audio playback',
        androidNotificationOngoing: true,
      ),
    );

    super.onInit();
  }

  void startTimer() {
    timer = Timer.periodic(const Duration(seconds: 1), (Timer timer) {
      Duration duration = Duration(seconds: timer.tick);
      if (Get.routing.current == Routes.CALL_SCREEN_ROUTE) {
        // this.setState(() {
        timeLabel.value = [duration.inMinutes, duration.inSeconds]
            .map((seg) => seg.remainder(60).toString().padLeft(2, '0'))
            .join(':');
        // });
      } else {
        timer.cancel();
      }
    });
  }

  void handelStreams(CallState event) async {
    final MediaStream? stream = event.stream;
    if (stream == null) return;

    if (event.originator == 'remote') {
      // Remote = inbound audio from peer. Route through earpiece by default
      // (speaker toggle on the call screen flips this).
      try {
        stream.getAudioTracks().first.enableSpeakerphone(false);
      } catch (_) {}
      remoteStream = stream;
      remoteRenderer?.srcObject = stream;
    } else {
      // Local = our mic stream. Ensure every audio track is explicitly
      // enabled — on some Android stacks the tracks come up disabled and
      // the only way to wake them up was to mute/unmute via SIP. Force
      // enabled here so audio flows from the moment the call connects.
      for (final t in stream.getAudioTracks()) {
        t.enabled = true;
      }
      localStream = stream;
    }
  }

  @override
  void callStateChanged(Call call, CallState callState) {
    if (callState.state == CallStateEnum.HOLD ||
        callState.state == CallStateEnum.UNHOLD) {
      hold.value = callState.state == CallStateEnum.HOLD;
      holdOriginator!.value = callState.originator?.toString() ?? '';
      // this.setState(() {});
      return;
    }

    if (callState.state == CallStateEnum.MUTED) {
      if (callState.audio!) audioMuted.value = true;
      if (callState.video!) videoMuted.value = true;
      // this.setState(() {});
      return;
    }

    if (callState.state == CallStateEnum.UNMUTED) {
      if (callState.audio!) audioMuted.value = false;
      if (callState.video!) videoMuted.value = false;
      // this.setState(() {});
      return;
    }

    if (callState.state != CallStateEnum.STREAM) {
      state.value = callState.state;
    }

    if (callState.state == CallStateEnum.FAILED) {
      // Navigator.pushNamed(context, '/callscreen', arguments: call);

      Get.back();
    }
    print("Session Start Time" + call.session.start_time.toString());
    if (call.session.start_time != null) {
      startTimer();
    }
// call.session.
    switch (callState.state) {
      case CallStateEnum.STREAM:
        handelStreams(callState);
        break;
      case CallStateEnum.ENDED:
        // if (Get.currentRoute == Routes.CALL_SCREEN_ROUTE) {
        //   Get.back();
        // }
        Get.back();
        break;
      case CallStateEnum.FAILED:
        // _backToDialPad();
        break;
      case CallStateEnum.UNMUTED:
        print("CallStateEnum.UNMUTED");
        break;
      case CallStateEnum.MUTED:
        print("CallStateEnum.MUTED");
        break;
      case CallStateEnum.CONNECTING:
        print("CallStateEnum.CONNECTING");
        break;
      case CallStateEnum.PROGRESS:
        print("CallStateEnum.PROGRESS");
        break;
      case CallStateEnum.ACCEPTED:
        state.value = CallStateEnum.ACCEPTED;
        print("CallStateEnum.ACCEPTED");
        break;
      case CallStateEnum.CONFIRMED:
        print("CallStateEnum.CONFIRMED");
        // Audio kickstart: on this Android stack the local mic track comes
        // up with `track.enabled = false` and the only way to flip it to
        // true is via sip_ua's _toggleMuteAudio(false), which is gated by
        // the internal _audioMuted flag. We force the cycle once so audio
        // flows from the moment the call connects (otherwise the user has
        // to manually tap Mute then Unmute). Done in a microtask so we
        // don't reentrantly mutate state during the callback.
        Future.microtask(() {
          if (call == null) return;
          try {
            call!.mute(true, false);
            call!.unmute(true, false);
            // sip_ua fires MUTED then UNMUTED callbacks which flip our
            // audioMuted observable up then down. Force it back to false
            // so the UI doesn't briefly show "Unmute" label.
            audioMuted.value = false;
          } catch (e) {
            print('Audio kickstart failed: $e');
          }
        });
        break;
      case CallStateEnum.HOLD:
        print("CallStateEnum.HOLD");
        break;
      case CallStateEnum.UNHOLD:
        print("CallStateEnum.UNHOLD");
        break;
      case CallStateEnum.NONE:
        print("CallStateEnum.NONE");
        break;
      case CallStateEnum.CALL_INITIATION:
        print("CallStateEnum.CALL_INITIATION");
        break;
      case CallStateEnum.REFER:
        print("CallStateEnum.REFER");
        break;
    }
  }

  @override
  void onNewMessage(SIPMessageRequest msg) {
    // TODO: implement onNewMessage
  }

  @override
  void registrationStateChanged(RegistrationState state) {
    // TODO: implement registrationStateChanged
  }

  @override
  void transportStateChanged(TransportState state) {
    // TODO: implement transportStateChanged
  }

  void handleDtmf(String tone) {
    print('Dtmf tone => $tone');
    call!.sendDTMF(tone);
  }

  void handleHangup({bool goBack = false}) {
    try {
      call!.hangup();
      timer!.cancel();
      goBack ? Get.back() : null;
    } catch (e) {
      timer!.cancel();
      goBack ? Get.back() : null;

      print(e.toString());
    }
  }

  void toggleSpeaker() {
    // if (localStream != null) {
    speakerOn.value = !speakerOn.value;
    if (!kIsWeb) {
      localStream!.getAudioTracks()[0].enableSpeakerphone(speakerOn.value);
    }
    // }
  }

  void turnOffSpeaker() {
    // if (localStream != null) {
    speakerOn.value = false;
    if (!kIsWeb) {
      localStream!.getAudioTracks()[0].enableSpeakerphone(speakerOn.value);
    }
    // }
  }

  void handleAccept() async {
    bool remote_has_video = call!.remote_has_video;
    final mediaConstraints = <String, dynamic>{
      'audio': true,
      'video': remote_has_video
    };
    MediaStream mediaStream;

    if (kIsWeb && remote_has_video) {
      mediaStream = await flwebrtc.navigator.mediaDevices
          .getDisplayMedia(mediaConstraints);
      mediaConstraints['video'] = false;
      MediaStream userStream =
          await flwebrtc.navigator.mediaDevices.getUserMedia(mediaConstraints);
      mediaStream.addTrack(userStream.getAudioTracks()[0], addToNative: true);
    } else {
      mediaConstraints['video'] = remote_has_video;
      mediaStream =
          await flwebrtc.navigator.mediaDevices.getUserMedia(mediaConstraints);
    }

    call!.answer(helper!.buildCallOptions(!remote_has_video),
        mediaStream: mediaStream);
    isIncomingCallAccepted!.value = true;
  }

  void switchCamera() {
    if (localStream != null) {
      Helper.switchCamera(localStream!.getVideoTracks()[0]);
    }
  }

  void muteAudio() {
    // Optimistic flip so the UI reacts instantly. The MUTED/UNMUTED state
    // callback from sip_ua sets the same value, so it's idempotent — no
    // toggle race like there used to be when the call site also flipped.
    final next = !audioMuted.value;
    audioMuted.value = next;
    if (next) {
      call!.mute(true, false);
    } else {
      call!.unmute(true, false);
    }
  }

  void muteVideo() {
    final next = !videoMuted.value;
    videoMuted.value = next;
    if (next) {
      call!.mute(false, true);
    } else {
      call!.unmute(false, true);
    }
  }

  void handleHold() {
    if (hold.value) {
      call!.unhold();
    } else {
      call!.hold();
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
  void onNewNotify(Object ntf) {
    // TODO: implement onNewNotify
  }

  @override
  void onNewReinvite(ReInvite event) {
    // TODO: implement onNewReinvite
  }
}

class MyAudioHandler extends BaseAudioHandler
    with
        QueueHandler, // mix in default queue callback implementations
        SeekHandler {
  // mix in default seek callback implementations
  CallScreenController controller;
  MyAudioHandler({required this.controller});
  // The most common callbacks:
  Future<void> play() async {
    if (controller.state.value == CallStateEnum.CONNECTING &&
        controller.call!.direction == 'INCOMING') {
      try {
        controller.handleAccept();
      } catch (e) {
        CustomToast.showToast(e.toString(), true);
      }
    }
  }

  Future<void> stop() async {
    try {
      controller.handleHangup();
    } catch (e) {
      CustomToast.showToast(e.toString(), true);
    }
  }
}
