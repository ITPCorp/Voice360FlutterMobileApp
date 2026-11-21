import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:shared_preferences/shared_preferences.dart';

class FullScreenCalls {
  FullScreenCalls._();
  static final instance = FullScreenCalls._();
  static const _channel = MethodChannel('voice360/app_wake');
  static const _dismissedAt = 'full_screen_calls_not_now_ms';
  static const _settingsOpened = 'full_screen_calls_awaiting_settings_return';
  final allowed = RxnBool();
  bool _consideringSheet = false;

  Future<void> check({bool Function()? mayPrompt}) async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
    bool? current;
    try {
      current = await _channel.invokeMethod<bool>('fsiAllowed');
    } on PlatformException {
      current = null;
    } on MissingPluginException {
      current = null;
    }
    final previous = allowed.value;
    allowed.value = current;
    if (current == null ||
        mayPrompt == null ||
        !mayPrompt() ||
        _consideringSheet) {
      return;
    }
    _consideringSheet = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      if (!mayPrompt() || allowed.value == null) return;

      final retry = prefs.getBool(_settingsOpened) ?? false;
      if (allowed.value == true) {
        if (retry) await prefs.remove(_settingsOpened);
        if (retry || previous == false) {
          _feedback('Full-screen incoming calls are on.');
        }
        return;
      }
      final now = DateTime.now().millisecondsSinceEpoch;
      final last = prefs.getInt(_dismissedAt);
      if (!retry &&
          last != null &&
          now >= last &&
          now - last < Duration.millisecondsPerDay) {
        return;
      }
      final context = Get.overlayContext;
      if (context == null ||
          !context.mounted ||
          !mayPrompt() ||
          allowed.value != false) {
        return;
      }
      final sheet = showModalBottomSheet<void>(
        context: context,
        useSafeArea: true,
        isScrollControlled: true,
        builder: (context) => SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Full-screen incoming calls',
                    style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 12),
                const Text(
                    'On the next screen, turn on Allow full screen notifications for Voice360.'),
                const SizedBox(height: 8),
                const Text(
                    'Android needs you to flip the switch so Voice360 can ring when your phone is locked.'),
                const SizedBox(height: 24),
                FilledButton(
                    onPressed: () async {
                      Navigator.pop(context);
                      await openSettings();
                    },
                    child: Text(retry ? 'Try again' : 'Open settings')),
                TextButton(
                    onPressed: () async {
                      await prefs.setInt(
                          _dismissedAt, DateTime.now().millisecondsSinceEpoch);
                      if (context.mounted) Navigator.pop(context);
                    },
                    child: const Text('Not now')),
              ],
            ),
          ),
        ),
      );
      if (retry) await prefs.remove(_settingsOpened);
      await sheet;
    } finally {
      _consideringSheet = false;
    }
  }

  Future<void> openSettings() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_settingsOpened, true);
    try {
      if (await _channel.invokeMethod<bool>('openFsiSettings') == true) return;
    } on PlatformException {
      // Some OEMs omit these settings activities.
    } on MissingPluginException {
      // The app activity may have detached.
    }
    await prefs.remove(_settingsOpened);
    _feedback('Open Android Settings, then Apps, Voice360, and Notifications.');
  }

  void _feedback(String message) {
    final context = Get.overlayContext;
    if (context != null && context.mounted) {
      ScaffoldMessenger.maybeOf(context)
          ?.showSnackBar(SnackBar(content: Text(message)));
    }
  }
}
