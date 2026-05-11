import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart' as flwebrtc;
import 'package:get/get.dart';
import 'package:itp_voice/helpers/config.dart';
import 'package:itp_voice/locator.dart';
import 'package:itp_voice/models/get_devices_reponse_model/devices.dart';
import 'package:itp_voice/repo/shares_preference_repo.dart';
import 'package:itp_voice/routes.dart';
import 'package:itp_voice/services/global_socket_service.dart';
import 'package:itp_voice/storage_keys.dart';
import 'package:itp_voice/widgets/custom_toast.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sip_ua/sip_ua.dart';

class BaseScreenController extends GetxController
    implements SipUaHelperListener {
  RxInt currentTab = 0.obs;

  SIPUAHelper? helper;

  @override
  void onInit() {
    // TODO: implement onInit
    helper = Get.find<SIPUAHelper>();
    _bindEventListeners();
    loadSettings();
    // Bring up the platform-wide notification socket (SMS, call events, etc.)
    // once the user is logged in and the base screen mounts. Fire-and-forget;
    // failures are handled with auto-reconnect inside the service.
    locator<GlobalSocketService>().connect();
    super.onInit();
  }

  updateCurrentTab(int val) {
    currentTab.value = val;
  }

  void _bindEventListeners() {
    helper!.addSipUaHelperListener(this);
  }

//   void loadSettings() async {
//   SharedPreferences _prefs = await SharedPreferences.getInstance();
//   String? _realm = _prefs.getString("realm") ?? "74682eda.dev.sip.itpvoice.net";
//   String? _username = _prefs.getString("username") ?? "ZqYlmbZwm5Qz";
//   String? _password = _prefs.getString("password") ?? "ELmXRZjVy0sGFCvYfeTkd5wO";

//   UaSettings settings = UaSettings();
//     _realm = "baf5108b.dev.sip.itpvoice.net";
//     _username= "D4RaeexMINxb";
//     _password= "cMzcikfaxK8Zjqg5xioVkZyX";
//   settings.webSocketUrl = "wss://ws.dev.sip.itpvoice.net:5066";
//   settings.webSocketSettings.extraHeaders = {
//     "Proxy-Authorization": "Digest realm=${_realm}"

//   };
//   settings.webSocketSettings.allowBadCertificate = true;
//   settings.uri = "sip:${_realm}";
//   settings.authorizationUser = "${_username}";
//   settings.password = "${_password}";
//   settings.displayName = "${_username}";
//   settings.userAgent = 'Dart SIP Client v1.0.0';
//   settings.dtmfMode = DtmfMode.RFC2833;

//   try {
//     print("Attempting to start SIP client with settings: ${settings.toString()}");
//     await helper!.start(settings);
//     print("SIP client started successfully.");
//   } catch (e) {
//     print("Error starting SIP client: $e");
//   }
// }

  loadSettings() {
    String? _realm = SharedPreferencesMethod.getString(StorageKeys.REALM);
    final device = SharedPreferencesMethod.getDeviceData();
    // Missing/invalid persisted state — typically an in-place upgrade from
    // a version that never wrote these keys, or a half-finished prior
    // login. Don't crash: bail to login so the user re-authenticates and
    // the prefs are rewritten with the current shape.
    if (device == null ||
        _realm == null ||
        _realm.isEmpty ||
        device.sipUsername == null ||
        device.sipPassword == null) {
      print('SIP loadSettings: missing/invalid persisted device — '
          'routing to login');
      // Clear the auth token so the login screen actually shows its form
      // (otherwise auto-login would loop us right back here on next launch).
      SharedPreferencesMethod.storage.remove(StorageKeys.REFRESH_TOKEN);
      SharedPreferencesMethod.storage.remove(StorageKeys.ACCESS_TOKEN);
      Get.offAllNamed(Routes.LOGIN_SCREEN_ROUTE);
      return;
    }
    final _username = device.sipUsername;
    final _password = device.sipPassword;

    UaSettings settings = UaSettings();

    settings.webSocketUrl = Config.WEB_SOCKET_URL;
    print(_realm);
    settings.webSocketSettings.extraHeaders = {
      "Proxy-Authorization": "Digest realm=${_realm}"
      ,"X-Auth-Token": "Bearer ${_password}",
      "X-Auth-User": "${_username}",
      "X-Auth-Realm": "${_realm}",
      "X-Auth-Password": "${_password}",
      "Sec-WebSocket-Protocol": "sip"

    };
    settings.webSocketSettings.allowBadCertificate = true;
    // settings.uri = "${_username}@${_realm}";
    settings.uri = "sip:${_username}@${_realm}";
    settings.authorizationUser = "${_username}";
    settings.password = "${_password}";
    settings.displayName = "${_username}";
    // settings.userAgent = 'Dart SIP Client v1.0.0';
    settings.userAgent = 'Flutter SIP Client v1.0';
    settings.dtmfMode = DtmfMode.INFO;
    settings.register = true;
    settings.transportType = TransportType.WS;
    settings.webSocketSettings.transport_scheme = "wss";
    settings.registrarServer = "sip:${_realm}";
    print("CONNECTED 222");
    print(helper!.registered);
    (helper!.start(settings));
  }

  @override
  void callStateChanged(Call call, CallState state) {
    // TODO: implement callStateChanged
    print(state.state);
    if (state.state == CallStateEnum.CALL_INITIATION) {
      // Navigator.pushNamed(context, '/callscreen', arguments: call);
      Get.toNamed(
        Routes.CALL_SCREEN_ROUTE,
        arguments: call,
      );
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

  Future<Widget?> handleCall(String number, BuildContext context,
      [bool voiceonly = true]) async {
    print(helper!.connected
        ? "SIP SERVER CONNECTED"
        : "SIP SERVER NOT CONNECTED");
    if (defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS) {
      final mic = await Permission.microphone.request();
      await Permission.camera.request();
      if (!mic.isGranted) {
        CustomToast.showToast('Microphone permission is required to place calls', true);
        return null;
      }
    }
    if (helper == null || !helper!.connected) {
      CustomToast.showToast(
          'Not connected to call server — check your internet and try again', true);
      // Nudge the registrar in case we got into a bad state.
      try { loadSettings(); } catch (_) {}
      return null;
    }
    if (number == null || number.isEmpty) {
      showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (BuildContext context) {
          return AlertDialog(
            title: Text('Target is empty.'),
            content: Text('Please enter a SIP URI or username!'),
            actions: <Widget>[
              TextButton(
                child: Text('Ok'),
                onPressed: () {
                  Navigator.of(context).pop();
                },
              ),
            ],
          );
        },
      );
      return null;
    }

    final mediaConstraints = <String, dynamic>{'audio': true, 'video': true};

    flwebrtc.MediaStream mediaStream;

    if (kIsWeb && !voiceonly) {
      mediaStream = await flwebrtc.navigator.mediaDevices
          .getDisplayMedia(mediaConstraints);
      mediaConstraints['video'] = false;
      flwebrtc.MediaStream userStream =
          await flwebrtc.navigator.mediaDevices.getUserMedia(mediaConstraints);
      mediaStream.addTrack(userStream.getAudioTracks()[0], addToNative: true);
    } else {
      mediaConstraints['video'] = !voiceonly;
      try {
        mediaStream =
            await flwebrtc.navigator.mediaDevices.getUserMedia(mediaConstraints);
        helper!.call(number, voiceOnly: voiceonly, mediaStream: mediaStream);
      } catch (e) {
        print('Call failed: $e');
        CustomToast.showToast('Could not start call: $e', true);
      }
      return null;
    }
  }

  @override
  void onNewNotify(Notify ntf) {
    // TODO: implement onNewNotify
  }

  @override
  void onNewReinvite(ReInvite event) {
    // TODO: implement onNewReinvite
  }

}



// UaSettings settings = UaSettings();
//     settings.webSocketUrl = "wss://ws.dev.sip.itpvoice.net:5066";
//     settings.webSocketSettings.extraHeaders = {
//       "Proxy-Authorization": "Digest realm=${_realm}"
//       ,"X-Auth-Token": "Bearer ${_password}",
//       "X-Auth-User": "${_username}",
//       "X-Auth-Realm": "${_realm}",
//       "X-Auth-Password": "${_password}",
//       "Sec-WebSocket-Protocol": "sip"

//     };
//     settings.webSocketSettings.allowBadCertificate = true;
//     // settings.uri = "${_username}@${_realm}";
//     settings.uri = "sip:${_username}@${_realm}";
//     settings.authorizationUser = "${_username}";
//     settings.password = "${_password}";
//     settings.displayName = "${_username}";
//     // settings.userAgent = 'Dart SIP Client v1.0.0';
//     settings.userAgent = 'Flutter SIP Client v1.0';
//     settings.dtmfMode = DtmfMode.INFO;
//     settings.register = true;
    // settings.transportType = TransportType.WS;
    // settings.webSocketSettings.transport_scheme = "wss";
    // settings.registrarServer = "sip:${_realm}";