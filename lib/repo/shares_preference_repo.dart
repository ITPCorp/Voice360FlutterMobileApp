import 'package:get/get.dart';
import 'package:itp_voice/models/get_devices_reponse_model/devices.dart';
import 'package:itp_voice/models/login_reponse_model/app_user.dart';
import 'package:itp_voice/storage_keys.dart';

import 'package:shared_preferences/shared_preferences.dart';

class SharedPreferencesMethod {
  static var storage = Get.find<SharedPreferences>();

  static Future<void> clearLocalStorage() async {
    storage.clear();
  }

  static Future<void> setbool(key, value) async {
    storage.setBool(key, value);
  }

  static bool? getBool(
      key,
      ) {
    bool? data = storage.getBool(key);
    return data;
  }

  static Future<void> setString(key, value) async {
    storage.setString(key, value);
  }


  static String? getString(
    key,
  ) {
    String? data = storage.getString(key);
    return data;
  }

  /// Returns null when the key is missing OR the persisted JSON can't be
  /// parsed into the current model. Crucially: NEVER throws — startup code
  /// gates on a null return and routes to login instead. The previous
  /// `getString(...)!` form threw `Null check operator used on a null value`
  /// during in-place upgrades from versions that hadn't written this key
  /// yet, causing the app to crash on launch until the user uninstalled.
  static AppUser? getUserData() {
    final keyValue = getString(StorageKeys.APPUSER_DATA);
    if (keyValue == null || keyValue.isEmpty) return null;
    try {
      return AppUser.fromJson(keyValue);
    } catch (_) {
      return null;
    }
  }

  /// See [getUserData] — same null-safe + tolerant contract.
  static Devices? getDeviceData() {
    final keyValue = getString(StorageKeys.DEVICE);
    if (keyValue == null || keyValue.isEmpty) return null;
    try {
      return Devices.fromJson(keyValue);
    } catch (_) {
      return null;
    }
  }
}
