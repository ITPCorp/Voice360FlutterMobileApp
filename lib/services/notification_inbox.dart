import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'notification_destination.dart';

/// Remove only delivered cards for the screen the user opened. IDs are read
/// from the OS so this works even when the process that posted them is gone.
class NotificationInbox {
  static const _channel = MethodChannel('voice360/notification_inbox');

  static Future<void> setVisibleThread(String? id) async {
    if (defaultTargetPlatform != TargetPlatform.android) return;
    try {
      await _channel.invokeMethod<void>('visibleThread', id);
    } on MissingPluginException {
      // No Android activity in widget tests or a headless engine.
    }
  }

  static String? androidTag(NotificationDestination? target) {
    if (target?.id == null) return null;
    final field = switch (target!.screen) {
      NotificationScreen.thread => 'message_thread_id',
      NotificationScreen.voicemail =>
        target.recordPk ? 'voicemail_message_pk' : 'voicemail_msg_id',
      _ => null,
    };
    return field == null
        ? null
        : 'voice360.inbox:${jsonEncode({field: target.id})}';
  }

  static Future<void> recent() =>
      _remove((target) => target.screen == NotificationScreen.recent);

  static Future<void> thread(String? id) async {
    if (id == null || id.isEmpty) return;
    await _remove((target) =>
        target.screen == NotificationScreen.thread && target.id == id);
  }

  static Future<void> voicemail(String? messageId, int? pk) =>
      _remove((target) =>
          target.screen == NotificationScreen.voicemail &&
          target.id != null &&
          target.id == (target.recordPk ? pk?.toString() : messageId));

  static Future<void> _remove(
      bool Function(NotificationDestination) matches) async {
    try {
      final rows = await _channel.invokeListMethod<dynamic>('active') ?? [];
      final keys = <Object>[];
      for (final row in rows.whereType<Map>()) {
        final key = row['key'];
        dynamic payload = row['payload'];
        if (payload is String) {
          try {
            payload = jsonDecode(payload);
          } on FormatException {
            continue;
          }
        }
        if (key == null || payload is! Map) continue;
        final target = NotificationDestination.parse(payload);
        if (target != null && matches(target)) keys.add(key);
      }
      if (keys.isNotEmpty) await _channel.invokeMethod<void>('remove', keys);
    } on MissingPluginException {
      // A background engine or widget test may have no notification center.
    } on PlatformException catch (error) {
      debugPrint(
          '[Notifications] Could not clear delivered alerts: ${error.code}');
    }
  }
}
