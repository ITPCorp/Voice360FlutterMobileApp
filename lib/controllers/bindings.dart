import 'package:get/get.dart';
import 'package:itp_voice/repo/base_requester.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:itp_voice/services/sip_settings.dart';

class Binding implements Bindings {
  @override
  void dependencies() async {
    await Get.putAsync<SharedPreferences>(() async {
      final prefs = await SharedPreferences.getInstance();
      return prefs;
    }, permanent: true);

    // The same instance the app-wake path may already have started.
    SipHolder.helper;

    await Get.put<BaseRequester>(BaseRequester(), permanent: true);
  }
}
