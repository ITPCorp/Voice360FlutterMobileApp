import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:shared_preferences/shared_preferences.dart';

class FullScreenCalls {
  FullScreenCalls._();
  static final instance = FullScreenCalls._();
  static const _channel = MethodChannel('voice360/app_wake');
  static const _shownAt = 'full_screen_calls_prompt_ms';
  final allowed = RxnBool();
  bool _consideringSheet = false;

  Future<void> check({bool Function()? mayPrompt}) async {
    if (!Platform.isAndroid) return;
    final previous = allowed.value;
    try {
      allowed.value = await _channel.invokeMethod<bool>('fsiAllowed');
    } on PlatformException {
      allowed.value = null;
    } on MissingPluginException {
      allowed.value = null;
    }
    if (previous == false && allowed.value == true) {
      _feedback('Full-screen incoming calls are on.');
    }
    if (allowed.value != false ||
        mayPrompt == null ||
        !mayPrompt() ||
        _consideringSheet) return;
    _consideringSheet = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      final now = DateTime.now().millisecondsSinceEpoch;
      final last = prefs.getInt(_shownAt);
      if (last != null &&
          now >= last &&
          now - last < Duration.millisecondsPerDay) return;
      final context = Get.overlayContext;
      if (context == null ||
          !context.mounted ||
          !mayPrompt() ||
          allowed.value != false) return;
      final sheet = showModalBottomSheet<bool>(
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
                    'Allow full-screen incoming calls so Voice360 can ring when your phone is locked.'),
                const SizedBox(height: 24),
                FilledButton(
                    onPressed: () => Navigator.pop(context, true),
                    child: const Text('Open settings')),
                TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text('Not now')),
              ],
            ),
          ),
        ),
      );
      await prefs.setInt(_shownAt, now);
      if (await sheet == true) await openSettings();
    } finally {
      _consideringSheet = false;
    }
  }

  Future<void> openSettings() async {
    try {
      if (await _channel.invokeMethod<bool>('openFsiSettings') == true) return;
    } on PlatformException {
      // Some OEMs omit these settings activities.
    } on MissingPluginException {
      // The app activity may have detached.
    }
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
