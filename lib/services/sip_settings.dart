import 'package:get/get.dart';
import 'package:itp_voice/helpers/config.dart';
import 'package:sip_ua/sip_ua.dart';

/// The one SIPUAHelper of the process. The wake path can start the UA before
/// any screen (and before GetX Binding) exists, so it is created here and
/// Binding registers this same instance.
class SipHolder {
  static final SIPUAHelper helper = () {
    if (Get.isRegistered<SIPUAHelper>()) return Get.find<SIPUAHelper>();
    final h = SIPUAHelper();
    Get.put<SIPUAHelper>(h, permanent: true);
    return h;
  }();
}

/// REGISTER expiry the app asks for. Kamailio keeps a binding until it expires
/// even when the app is killed (usrloc has no handle_lost_tcp), and while it
/// looks registered the dialplan dials it instead of pushing. 120 s keeps that
/// window short; sip_ua refreshes it while the UA runs.
const int kRegisterExpires = 120;

/// UA settings for the user's app_phone device (same shape the app used before
/// app-wake; only the expiry is new).
UaSettings buildUaSettings({
  required String realm,
  required String username,
  required String password,
}) {
  final settings = UaSettings();
  settings.webSocketUrl = Config.WEB_SOCKET_URL;
  settings.webSocketSettings.extraHeaders = {
    "Proxy-Authorization": "Digest realm=$realm",
    "X-Auth-Token": "Bearer $password",
    "X-Auth-User": username,
    "X-Auth-Realm": realm,
    "X-Auth-Password": password,
    "Sec-WebSocket-Protocol": "sip"
  };
  settings.webSocketSettings.allowBadCertificate = true;
  settings.uri = "sip:$username@$realm";
  settings.authorizationUser = username;
  settings.password = password;
  settings.displayName = username;
  settings.userAgent = 'Flutter SIP Client v1.0';
  settings.dtmfMode = DtmfMode.INFO;
  settings.register = true;
  settings.register_expires = kRegisterExpires;
  settings.transportType = TransportType.WS;
  settings.webSocketSettings.transport_scheme = "wss";
  settings.registrarServer = "sip:$realm";
  return settings;
}
