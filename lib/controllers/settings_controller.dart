import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:itp_voice/repo/contacts_repo.dart';

import '../repo/shares_preference_repo.dart';
import '../storage_keys.dart';

/// Tri-state app theme preference. `system` honours the OS dark-mode toggle.
enum AppThemeMode { system, light, dark }

class SettingsController extends GetxController {
  ContactsRepo contactsRepo = ContactsRepo();

  RxBool isPhoneEditing = false.obs;
  TextEditingController myNumberController =
      TextEditingController(text: Get.arguments?.toString() ?? '');

  RxBool isLoading = false.obs;

  /// Current effective theme preference. Defaults to `system`.
  Rx<AppThemeMode> themeMode = AppThemeMode.system.obs;

  /// Legacy alias kept so the settings screen toggle (which switches between
  /// "dark on" / "dark off") still works. `true` only when forced dark.
  RxBool get isDark => RxBool(themeMode.value == AppThemeMode.dark);

  Future<void> updateNumber() async {
    isLoading.value = true;
    try {
      await contactsRepo.updateMyNumber(myNumberController.text);
    } catch (_) {
      myNumberController.text = Get.arguments?.toString() ?? '';
    }
    isLoading.value = false;
  }

  @override
  void onInit() {
    super.onInit();
    // DARK_THEME was historically stored as a bool; tolerate the legacy type
    // so we don't crash older installs.
    String? stored;
    try {
      stored = SharedPreferencesMethod.storage.getString(StorageKeys.DARK_THEME);
    } catch (_) {
      stored = null;
    }
    if (stored == 'light') {
      themeMode.value = AppThemeMode.light;
    } else if (stored == 'dark') {
      themeMode.value = AppThemeMode.dark;
    } else {
      themeMode.value = AppThemeMode.system;
    }
    // Defer until after the current frame: onInit can run synchronously
    // while the settings screen is mid-build (Get.put inside build()), and
    // Get.changeThemeMode flips the root GetMaterialApp -> setState during
    // build error.
    WidgetsBinding.instance.addPostFrameCallback((_) => _applyThemeMode());
  }

  void setThemeMode(AppThemeMode mode) {
    themeMode.value = mode;
    final v = switch (mode) {
      AppThemeMode.system => 'system',
      AppThemeMode.light => 'light',
      AppThemeMode.dark => 'dark',
    };
    SharedPreferencesMethod.storage.setString(StorageKeys.DARK_THEME, v);
    _applyThemeMode();
  }

  /// Legacy toggle used by SwitchListTile: true → force dark, false → system.
  void changeTheme(bool darkOn) {
    setThemeMode(darkOn ? AppThemeMode.dark : AppThemeMode.system);
  }

  void _applyThemeMode() {
    final flutterMode = switch (themeMode.value) {
      AppThemeMode.system => ThemeMode.system,
      AppThemeMode.light => ThemeMode.light,
      AppThemeMode.dark => ThemeMode.dark,
    };
    Get.changeThemeMode(flutterMode);
  }
}
