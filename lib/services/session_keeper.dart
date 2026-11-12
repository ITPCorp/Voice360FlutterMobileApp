import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:get/get.dart';
import 'package:itp_voice/repo/auth_repo.dart';
import 'package:itp_voice/repo/base_requester.dart';

/// Keeps a signed-in user signed in by trading the session token for a new
/// one at `/auth/refresh` (tokens last 24 h; any unexpired token can be
/// refreshed). This replaced the saved password that the app used to replay
/// on a 401.
///
/// Refreshes:
///   * at app start (LoginController, before the user lands in the app),
///   * when the app comes back to the foreground, if the last refresh is
///     older than [minGap],
///   * every [interval] while the app is in the foreground.
///
/// A 401 from refresh means the token is dead: [onExpired] runs (by default
/// the shared 401 handler, which logs out and opens the login screen with
/// the email prefilled). Network errors keep the token and wait for the
/// next tick.
class SessionKeeper with WidgetsBindingObserver {
  SessionKeeper({
    Future<RefreshStatus> Function()? refresh,
    this.interval = const Duration(minutes: 30),
    this.minGap = const Duration(minutes: 5),
    Future<void> Function()? onExpired,
  })  : _refresh = refresh ?? (() => AuthRepo().refreshSession()),
        _onExpired = onExpired ??
            (() => Get.find<BaseRequester>().handleUnauthorized());

  final Future<RefreshStatus> Function() _refresh;
  final Future<void> Function() _onExpired;
  final Duration interval;
  final Duration minGap;

  Timer? _timer;
  bool _running = false;
  DateTime? _lastOk;
  Future<RefreshStatus>? _inFlight;

  bool get isRunning => _running;
  DateTime? get lastRefresh => _lastOk;

  /// Start keeping the session alive. [fresh] = a token was just minted
  /// (sign-in or a successful refresh). Pass false after a failed start-up
  /// refresh so the next resume retries straight away.
  void start({bool fresh = true}) {
    if (fresh) _lastOk = DateTime.now();
    if (_running) return;
    _running = true;
    WidgetsBinding.instance.addObserver(this);
    _schedule();
  }

  /// Stop (logout, expired session).
  void stop() {
    if (!_running) return;
    _running = false;
    _timer?.cancel();
    _timer = null;
    WidgetsBinding.instance.removeObserver(this);
  }

  /// Refresh now. Concurrent callers share one request.
  Future<RefreshStatus> refreshNow() {
    return _inFlight ??= _doRefresh().whenComplete(() => _inFlight = null);
  }

  Future<RefreshStatus> _doRefresh() async {
    RefreshStatus status;
    try {
      status = await _refresh();
    } catch (e) {
      // ignore: avoid_print
      print('[Session] refresh threw: $e');
      status = RefreshStatus.failed;
    }
    switch (status) {
      case RefreshStatus.ok:
        _lastOk = DateTime.now();
        break;
      case RefreshStatus.expired:
        if (_running) {
          stop();
          await _onExpired();
        }
        break;
      case RefreshStatus.noSession:
        stop();
        break;
      case RefreshStatus.failed:
        break;
    }
    return status;
  }

  void _schedule() {
    _timer?.cancel();
    _timer = Timer.periodic(interval, (_) => refreshNow());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!_running) return;
    if (state == AppLifecycleState.resumed) {
      final last = _lastOk;
      if (last == null || DateTime.now().difference(last) >= minGap) {
        refreshNow();
      }
      _schedule();
    } else if (state == AppLifecycleState.paused) {
      // The OS suspends timers in the background anyway; resume catches up.
      _timer?.cancel();
      _timer = null;
    }
  }
}
