import 'dart:convert';
import 'dart:io' show Platform;

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:itp_voice/design/v360.dart';
import 'package:itp_voice/helpers/config.dart';
import 'package:itp_voice/services/app_wake/call_wake_service.dart';
import 'package:sip_ua/sip_ua.dart';
import 'package:itp_voice/locator.dart';
import 'package:itp_voice/main.dart' show firebaseReady;
import 'package:itp_voice/repo/base_requester.dart';
import 'package:itp_voice/repo/shares_preference_repo.dart';
import 'package:itp_voice/routes.dart';
import 'package:itp_voice/services/demo_mode_service.dart';
import 'package:itp_voice/services/global_socket_service.dart';
import 'package:itp_voice/services/push_service.dart';
import 'package:itp_voice/storage_keys.dart';
import 'package:itp_voice/widgets/custom_toast.dart';

/// Hidden diagnostics screen. Reached by tapping the avatar on the profile
/// screen 7 times. Not exposed in routes.dart on purpose — internal only.
class DebugScreen extends StatefulWidget {
  const DebugScreen({super.key});

  @override
  State<DebugScreen> createState() => _DebugScreenState();
}

class _DebugScreenState extends State<DebugScreen> {
  static const _wake = MethodChannel('voice360/app_wake');
  List<String> _routeEvents = [];
  bool _loading = true;

  Future<List<String>> _readRouteTrace() async {
    final rows = await _wake.invokeListMethod<dynamic>('routeTrace') ?? [];
    return rows.map(jsonEncode).toList();
  }

  Future<void> _copyRouteTrace() async {
    final rows = await _readRouteTrace();
    await Clipboard.setData(ClipboardData(text: rows.join('\n')));
    if (!mounted) return;
    setState(() => _routeEvents = rows);
    CustomToast.showToast('Route trace copied (${rows.length})', false);
  }
  String? _firebaseAppName;
  String? _firebaseAppOptionsAppId;
  String? _fcmCached;
  String? _fcmLive;
  String? _storedRefreshToken;
  String? _storedAccessToken;
  String? _apiId;
  String? _userId;
  String? _defaultNumber;
  String? _extension;
  bool _socketConnected = false;
  String? _fcmError;
  String? _backendStoredToken;
  String? _backendStoredEmail;
  String? _backendStoredPk;
  String? _backendError;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    setState(() => _loading = true);
    String? firebaseAppName;
    String? firebaseAppOptionsAppId;
    try {
      final app = Firebase.app();
      firebaseAppName = app.name;
      firebaseAppOptionsAppId = app.options.appId;
    } catch (e) {
      firebaseAppName = null;
      firebaseAppOptionsAppId = e.toString();
    }

    String? fcmLive;
    String? fcmError;
    try {
      fcmLive = await FirebaseMessaging.instance.getToken();
    } catch (e) {
      fcmError = e.toString();
    }

    // Hit /myprofile to see what the backend actually has stored against this
    // account. The mobile_device_id field is what FCM messages get targeted to.
    String? storedToken;
    String? storedEmail;
    String? storedPk;
    String? backendError;
    try {
      final resp = await BaseRequesterMethods.baseRequester
          .baseGetAPI(Endpoints.USER_PROFILE);
      if (resp is Map) {
        final result = resp['result'];
        if (result is Map) {
          storedToken = result['mobile_device_id']?.toString();
          storedEmail = result['email']?.toString();
          storedPk = result['pk']?.toString();
        } else {
          backendError = 'unexpected response shape';
        }
      } else {
        backendError = 'no response';
      }
    } catch (e) {
      backendError = e.toString();
    }

    final routeEvents = Platform.isIOS ? await _readRouteTrace() : <String>[];
    if (!mounted) return;
    setState(() {
      _routeEvents = routeEvents;
      _firebaseAppName = firebaseAppName;
      _firebaseAppOptionsAppId = firebaseAppOptionsAppId;
      _fcmCached = locator<PushService>().cachedToken;
      _fcmLive = fcmLive;
      _fcmError = fcmError;
      _storedRefreshToken =
          SharedPreferencesMethod.storage.getString(StorageKeys.REFRESH_TOKEN);
      _storedAccessToken =
          SharedPreferencesMethod.storage.getString(StorageKeys.ACCESS_TOKEN);
      _apiId = SharedPreferencesMethod.storage.getString(StorageKeys.API_ID);
      _userId = SharedPreferencesMethod.storage.getString(StorageKeys.USER_ID);
      _defaultNumber = SharedPreferencesMethod.storage
          .getString(StorageKeys.DEFAULT_NUMBER);
      _extension =
          SharedPreferencesMethod.storage.getString(StorageKeys.EXTENTION);
      _socketConnected = locator<GlobalSocketService>().isConnected;
      _backendStoredToken = storedToken;
      _backendStoredEmail = storedEmail;
      _backendStoredPk = storedPk;
      _backendError = backendError;
      _loading = false;
    });
  }

  Future<void> _resendTokenToBackend() async {
    final t = await locator<PushService>().onLoginSuccess();
    if (t == null) {
      CustomToast.showToast(
        'Could not fetch FCM token — see logs.',
        true,
      );
      return;
    }
    CustomToast.showToast(
      'Got token. Re-login to push it to backend.',
      false,
    );
    _refresh();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Debug'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _refresh,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(strokeWidth: 2.4))
          : ListView(
              padding: const EdgeInsets.all(V360Spacing.s4),
              children: [
                _section('Demo mode (Play Store screenshots)', [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'When ON, the messages list, chat threads, and call history use curated fake data. Toggle, then pull-to-refresh each screen.',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ),
                      Switch(
                        value: DemoModeService.instance.enabled,
                        onChanged: (v) async {
                          await DemoModeService.instance.setEnabled(v);
                          setState(() {});
                          CustomToast.showToast(
                            v
                                ? 'Demo mode ON. Pull-to-refresh tabs.'
                                : 'Demo mode OFF.',
                            false,
                          );
                        },
                      ),
                    ],
                  ),
                ]),
                _section('Firebase', [
                  _kv('firebaseReady (flag)', firebaseReady.toString()),
                  _kv('app.name', _firebaseAppName ?? '(no app)'),
                  _kv('app.options.appId', _firebaseAppOptionsAppId ?? '—'),
                  if (_fcmError != null) _kv('getToken error', _fcmError!),
                ]),
                _section('FCM token', [
                  _kvLong('PushService cached', _fcmCached),
                  _kvLong('Live (just fetched)', _fcmLive),
                  const SizedBox(height: V360Spacing.s2),
                  Row(
                    children: [
                      OutlinedButton.icon(
                        onPressed: _resendTokenToBackend,
                        icon: const Icon(Icons.refresh_rounded, size: 16),
                        label: const Text('Refresh + cache token'),
                      ),
                    ],
                  ),
                ]),
                _section('Backend (/myprofile)', [
                  if (_backendError != null)
                    _kv('error', _backendError!)
                  else ...[
                    _kv('email', _backendStoredEmail ?? '—'),
                    _kv('pk', _backendStoredPk ?? '—'),
                    _kvLong('mobile_device_id', _backendStoredToken),
                    _tokenMatchRow(),
                  ],
                ]),
                _section('Auth / session', [
                  _kvLong('REFRESH_TOKEN', _storedRefreshToken),
                  _kvLong('ACCESS_TOKEN', _storedAccessToken),
                  _kv('API_ID', _apiId ?? '—'),
                  _kv('USER_ID', _userId ?? '—'),
                  _kv('DEFAULT_NUMBER', _defaultNumber ?? '—'),
                  _kv('EXTENSION', _extension ?? '—'),
                ]),
                _section('Incoming calls (app-wake)', [
                  _kv('backend', '${Config.ENV} · ${Config.WEB_SOCKET_URL}'),
                  _kv('SIP registered', Get.find<SIPUAHelper>().registered.toString()),
                  _kvLong('VoIP token (iOS)', CallWakeService.instance.voipToken),
                  Obx(() {
                    final rows = CallWakeService.instance.recentTimings;
                    if (rows.isEmpty) return _kv('wake timings', 'none yet');
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (final r in rows)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 4),
                            child: SelectableText(r,
                                style: const TextStyle(fontSize: 11, fontFamily: 'monospace')),
                          ),
                      ],
                    );
                  }),
                  Row(children: [
                    OutlinedButton.icon(
                      onPressed: () async {
                        final rows = await CallWakeService.instance.timingRows();
                        await Clipboard.setData(ClipboardData(text: rows.join('\n')));
                        CustomToast.showToast('Wake timings copied (${rows.length})', false);
                      },
                      icon: const Icon(Icons.copy_rounded, size: 16),
                      label: const Text('Copy timings JSON'),
                    ),
                  ]),
                ]),
                if (Platform.isIOS)
                  _section('Audio route trace', [
                    if (_routeEvents.isEmpty) const Text('No route events yet.'),
                    for (final event in _routeEvents.reversed)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: SelectableText(event, style: Theme.of(context).textTheme.bodySmall),
                      ),
                    TextButton.icon(
                      onPressed: _copyRouteTrace,
                      icon: const Icon(Icons.copy_rounded, size: 16),
                      label: const Text('Copy route trace'),
                    ),
                  ]),
                _section('Global notification socket', [
                  _kv('connected', _socketConnected.toString()),
                  _kv('endpoint', 'wss://ws.cloud.itp360.com/ws'),
                ]),
                const SizedBox(height: V360Spacing.s8),
                Text(
                  'Internal diagnostics. If you got here by accident, swipe back.',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                ),
              ],
            ),
    );
  }

  Widget _section(String title, List<Widget> rows) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: V360Spacing.s5),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: V360Spacing.s2, left: V360Spacing.s2),
            child: Text(
              title.toUpperCase(),
              style: TextStyle(
                color: cs.onSurfaceVariant,
                fontSize: 12,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.6,
              ),
            ),
          ),
          V360Card(
            padding: const EdgeInsets.all(V360Spacing.s3),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: rows,
            ),
          ),
        ],
      ),
    );
  }

  Widget _kv(String k, String v) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 140,
            child: Text(
              k,
              style: tt.labelMedium?.copyWith(
                color: cs.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(
            child: Text(
              v,
              style: tt.bodyMedium?.copyWith(fontFamily: 'monospace'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _tokenMatchRow() {
    final live = _fcmLive ?? _fcmCached;
    final stored = _backendStoredToken;
    if (live == null || stored == null) {
      return const SizedBox.shrink();
    }
    final matches = live == stored;
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: V360Spacing.s2),
      child: Row(
        children: [
          Icon(
            matches ? Icons.check_circle : Icons.error_outline_rounded,
            color: matches ? V360Colors.success500 : V360Colors.danger500,
            size: 18,
          ),
          const SizedBox(width: V360Spacing.s2),
          Expanded(
            child: Text(
              matches
                  ? 'Backend has the current device token. Pushes should land.'
                  : 'Backend token does NOT match this device. Log out / in to re-register.',
              style: TextStyle(
                color: matches ? V360Colors.success700 : V360Colors.danger700,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _kvLong(String k, String? v) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final value = (v == null || v.isEmpty) ? '(empty)' : v;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  k,
                  style: tt.labelMedium?.copyWith(color: cs.onSurfaceVariant),
                ),
              ),
              if (v != null && v.isNotEmpty)
                IconButton(
                  icon: const Icon(Icons.copy_rounded, size: 16),
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  onPressed: () async {
                    await Clipboard.setData(ClipboardData(text: v));
                    CustomToast.showToast('Copied.', false);
                  },
                ),
            ],
          ),
          const SizedBox(height: 2),
          SelectableText(
            value,
            style: tt.bodySmall?.copyWith(fontFamily: 'monospace'),
          ),
        ],
      ),
    );
  }
}
