// Auth repo: password login, two-factor code step, session refresh, and the
// removal of the saved password (#52888). All HTTP is mocked with
// package:http/testing.dart; nothing here reaches a real server.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:itp_voice/repo/auth_repo.dart';
import 'package:itp_voice/repo/base_requester.dart';
import 'package:itp_voice/routes.dart';
import 'package:itp_voice/services/session_keeper.dart';
import 'package:itp_voice/storage_keys.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:itp_voice/services/saved_login.dart';

const _apiId = 'api-123';

Map<String, dynamic> _session(String token) => {
      'pk': 7,
      'email': 'user@example.com',
      'firstname': 'Test',
      'time_zone': 'America/New_York',
      'access_token': token,
      'refresh_token': token,
    };

http.Response _json(Object body, [int status = 200]) =>
    http.Response(jsonEncode(body), status,
        headers: {'content-type': 'application/json'});

/// Answers for the calls made after a session is minted (services, realm,
/// devices, user id). Records every request in [log].
http.Response? _postLoginChain(http.Request req) {
  final url = req.url.toString();
  if (url == Endpoints.SERVICES_URL) {
    return _json({
      'errors': false,
      'result': [
        {
          'api_id': _apiId,
          'product': {'item_type': 'itp_voice'}
        }
      ],
    });
  }
  if (url == Endpoints.GET_ACCOUNT_DETAILS(_apiId)) {
    return _json({
      'errors': false,
      'result': {'realm': 'test.realm'}
    });
  }
  if (url == Endpoints.GET_DEVICES_URL(_apiId)) {
    return _json({
      'errors': false,
      'result': [
        {
          'pk': 1,
          'device_type': 'app_phone',
          'sip_username': 'u',
          'sip_password': 'p'
        }
      ],
    });
  }
  if (url == Endpoints.GET_USER_DATA(_apiId)) {
    return _json({
      'errors': false,
      'message': 'User details',
      'result': {
        'pk': 55,
        'presence_id': '101',
        'voice_account': {'default_outbound_callerid_number': '+13055550100'},
      },
    });
  }
  return null;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late SharedPreferences prefs;
  late List<http.Request> log;

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    Get.put<SharedPreferences>(prefs, permanent: true);
    Get.put<BaseRequester>(BaseRequester(), permanent: true);
  });

  setUp(() async {
    await prefs.clear();
    FlutterSecureStorage.setMockInitialValues({});
    log = [];
  });

  Future<SavedCredentials?> saved() => SavedLogin().read();

  Future<T> withHttp<T>(
      Future<T> Function() body, http.Response Function(http.Request) handler) {
    final client = MockClient((req) async {
      log.add(req);
      return _postLoginChain(req) ?? handler(req);
    });
    return http.runWithClient(body, () => client);
  }

  AuthRepo repo() => AuthRepo(pushTokenProvider: () async => 'fcm-1');

  group('Remember me (secure store)', () {
    test('2.1.9 plain-text login moves to the secure store, session kept',
        () async {
      await prefs.setString(StorageKeys.EMAIL, 'user@example.com');
      await prefs.setString(StorageKeys.PASSWORD, 'hunter2');
      await prefs.setBool(StorageKeys.REMEMBER, true);
      await prefs.setString(StorageKeys.REFRESH_TOKEN, 'tok-old');

      await SavedLogin().migrateLegacy(prefs);

      final c = await saved();
      expect(c?.email, 'user@example.com');
      expect(c?.password, 'hunter2');
      expect(prefs.getString(StorageKeys.PASSWORD), isNull);
      expect(prefs.getBool(StorageKeys.REMEMBER), isTrue);
      expect(prefs.getString(StorageKeys.REFRESH_TOKEN), 'tok-old');
    });

    test('plain password without Remember me is deleted, nothing saved',
        () async {
      await prefs.setString(StorageKeys.EMAIL, 'user@example.com');
      await prefs.setString(StorageKeys.PASSWORD, 'hunter2');
      await prefs.setBool(StorageKeys.REMEMBER, false);
      await SavedLogin().migrateLegacy(prefs);
      expect(await saved(), isNull);
      expect(prefs.getString(StorageKeys.PASSWORD), isNull);
    });

    test('login with Remember me saves it; without, forgets it', () async {
      ok(req) => _json({'errors': false, 'result': _session('tok-A')});
      await withHttp(() => repo().loginUser('user@example.com', 's3cret'), ok);
      expect((await saved())?.password, 's3cret');
      await withHttp(
          () => repo().loginUser('user@example.com', 's3cret', remember: false), ok);
      expect(await saved(), isNull);
      expect(prefs.getBool(StorageKeys.REMEMBER), isFalse);
    });

    test('silent re-login with the saved login gets a new session', () async {
      await SavedLogin().save('user@example.com', 's3cret');
      final res = await withHttp(() => repo().signInWithSavedLogin(), (req) {
        expect(jsonDecode(req.body)['password'], 's3cret');
        return _json({'errors': false, 'result': _session('tok-B')});
      });
      expect(res, isTrue);
      expect(prefs.getString(StorageKeys.REFRESH_TOKEN), 'tok-B');
    });

    test('silent re-login: nothing saved -> null, no request', () async {
      final res = await withHttp(() => repo().signInWithSavedLogin(),
          (req) => fail('no request expected'));
      expect(res, isNull);
      expect(log, isEmpty);
    });

    test('silent re-login: password changed (401) forgets the saved login',
        () async {
      await SavedLogin().save('user@example.com', 'old');
      final res = await withHttp(() => repo().signInWithSavedLogin(),
          (req) => _json({'errors': true, 'message': 'Invalid credentials'}, 401));
      expect(res, 'Invalid credentials');
      expect(await saved(), isNull);
    });

    test('silent re-login: server error keeps the saved login', () async {
      await SavedLogin().save('user@example.com', 's3cret');
      await withHttp(() => repo().signInWithSavedLogin(),
          (req) => _json({'errors': true, 'message': 'oops'}, 500));
      expect((await saved())?.password, 's3cret');
    });

    test('silent re-login, 2FA on: challenge only, code alone finishes it',
        () async {
      await SavedLogin().save('user@example.com', 's3cret');
      final r = repo();
      final res = await withHttp(() => r.signInWithSavedLogin(),
          (req) => _json({
                'errors': false,
                'result': {'requires_mfa': true, 'temp_token': 'temp-9', 'expires_in': 600},
              }));
      expect(res, isA<MfaChallenge>());
      final done = await withHttp(() => r.verifyMfaCode(res as MfaChallenge, '123456'),
          (req) {
        expect(req.url.toString(), Endpoints.VERIFY_2FA_URL);
        expect(jsonDecode(req.body)['code'], '123456');
        return _json({'errors': false, 'result': _session('tok-C')});
      });
      expect(done, isTrue);
      expect(prefs.getString(StorageKeys.REFRESH_TOKEN), 'tok-C');
      expect((await saved())?.password, 's3cret');
    });
  });

  group('password login', () {
    test('without 2FA stores the token and the email; password only in the secure store',
        () async {
      final res = await withHttp(
          () => repo().loginUser('user@example.com', 's3cret'), (req) {
        expect(req.url.toString(), Endpoints.LOGIN_URL);
        final body = jsonDecode(req.body);
        expect(body['username'], 'user@example.com');
        expect(body['mobile_device_id'], 'fcm-1');
        return _json(
            {'errors': false, 'message': 'Logged in', 'result': _session('tok-A')});
      });

      expect(res, isTrue);
      expect(prefs.getString(StorageKeys.REFRESH_TOKEN), 'tok-A');
      expect(prefs.getString(StorageKeys.ACCESS_TOKEN), 'tok-A');
      expect(prefs.getString(StorageKeys.EMAIL), 'user@example.com');
      expect(prefs.getString(StorageKeys.PASSWORD), isNull);
      expect(prefs.getString(StorageKeys.API_ID), _apiId);
      expect(prefs.getString(StorageKeys.USER_ID), '55');
      expect((await saved())?.password, 's3cret');
      // Nothing in SharedPreferences contains the password.
      for (final k in prefs.getKeys()) {
        expect(prefs.get(k).toString().contains('s3cret'), isFalse, reason: k);
      }
    });

    test('wrong password returns the server message, no token', () async {
      final res = await withHttp(() => repo().loginUser('user@example.com', 'bad'),
          (req) => _json({'errors': true, 'message': 'Invalid credentials'}, 401));
      expect(res, 'Invalid credentials');
      expect(prefs.getString(StorageKeys.REFRESH_TOKEN), isNull);
    });

    test('429 passes the rate-limit message through', () async {
      final res = await withHttp(
          () => repo().loginUser('user@example.com', 'x'),
          (req) => _json({
                'errors': true,
                'message': 'Too many login attempts. Please try again later.'
              }, 429));
      expect(res, 'Too many login attempts. Please try again later.');
    });

    test('2FA on: returns a challenge and stores nothing', () async {
      final res = await withHttp(
          () => repo().loginUser('user@example.com', 's3cret'),
          (req) => _json({
                'errors': false,
                'message': 'Two-factor code required',
                'result': {
                  'requires_mfa': true,
                  'mfa_methods': ['totp'],
                  'temp_token': 'temp-1',
                  'expires_in': 600,
                },
              }));

      expect(res, isA<MfaChallenge>());
      final c = res as MfaChallenge;
      expect(c.tempToken, 'temp-1');
      expect(c.methods, ['totp']);
      expect(c.email, 'user@example.com');
      expect(c.pushToken, 'fcm-1');
      expect(c.isExpired, isFalse);
      expect(prefs.getString(StorageKeys.REFRESH_TOKEN), isNull);
      expect(prefs.getString(StorageKeys.ACCESS_TOKEN), isNull);
      // Only the login call went out, not the post-login chain.
      expect(log.length, 1);
    });
  });

  group('2FA verify', () {
    MfaChallenge challenge({Duration ttl = const Duration(minutes: 10)}) =>
        MfaChallenge(
          tempToken: 'temp-1',
          methods: const ['totp'],
          expiresAt: DateTime.now().add(ttl),
          email: 'user@example.com',
          pushToken: 'fcm-1',
        );

    test('right code signs in like a normal login', () async {
      final res = await withHttp(() => repo().verifyMfaCode(challenge(), '123456'),
          (req) {
        expect(req.url.toString(), Endpoints.VERIFY_2FA_URL);
        expect(req.method, 'POST');
        expect(req.headers['Authorization'], 'Bearer temp-1');
        final body = jsonDecode(req.body);
        expect(body['code'], '123456');
        expect(body['mobile_device_id'], 'fcm-1');
        return _json(
            {'errors': false, 'message': 'Logged in', 'result': _session('tok-B')});
      });
      expect(res, isTrue);
      expect(prefs.getString(StorageKeys.REFRESH_TOKEN), 'tok-B');
      expect(prefs.getString(StorageKeys.EMAIL), 'user@example.com');
    });

    test('wrong code: message, stay on the code step', () async {
      final res = await withHttp(() => repo().verifyMfaCode(challenge(), '000000'),
          (req) => _json({'errors': true, 'message': 'Invalid code'}, 401));
      expect(res, isA<AuthFailure>());
      expect((res as AuthFailure).message, 'Invalid code');
      expect(res.restart, isFalse);
      expect(prefs.getString(StorageKeys.REFRESH_TOKEN), isNull);
    });

    test('expired temp token: restart from the password step', () async {
      final res = await withHttp(
          () => repo().verifyMfaCode(challenge(), '000000'),
          (req) => _json({
                'errors': true,
                'message': 'Invalid or expired sign-in. Start again.'
              }, 401));
      expect((res as AuthFailure).restart, isTrue);
    });

    test('locked out: 429 message', () async {
      final res = await withHttp(
          () => repo().verifyMfaCode(challenge(), '000000'),
          (req) => _json(
              {'errors': true, 'message': 'Too many attempts. Try again later.'},
              429));
      expect((res as AuthFailure).message, 'Too many attempts. Try again later.');
      expect(res.restart, isFalse);
    });

    test('challenge past its expiry does not call the server', () async {
      final res = await withHttp(
          () => repo().verifyMfaCode(challenge(ttl: const Duration(seconds: -1)), '123456'),
          (req) => fail('no request expected'));
      expect((res as AuthFailure).restart, isTrue);
      expect(log, isEmpty);
    });
  });

  group('refresh', () {
    test('no token: noSession, no request', () async {
      final res = await withHttp(() => repo().refreshSession(),
          (req) => fail('no request expected'));
      expect(res, RefreshStatus.noSession);
    });

    test('ok: sends the stored token, stores the new one', () async {
      await prefs.setString(StorageKeys.REFRESH_TOKEN, 'tok-old');
      final res = await withHttp(() => repo().refreshSession(), (req) {
        expect(req.method, 'GET');
        expect(req.url.toString(), Endpoints.REFRESH_TOKEN_URL);
        expect(req.headers['Authorization'], 'Bearer tok-old');
        return _json(
            {'errors': false, 'message': 'Logged in', 'result': _session('tok-new')});
      });
      expect(res, RefreshStatus.ok);
      expect(prefs.getString(StorageKeys.REFRESH_TOKEN), 'tok-new');
      expect(prefs.getString(StorageKeys.ACCESS_TOKEN), 'tok-new');
      expect(prefs.getString(StorageKeys.APPUSER_DATA), contains('tok-new'));
    });

    test('401: expired, token left for the caller to clear', () async {
      await prefs.setString(StorageKeys.REFRESH_TOKEN, 'tok-old');
      final res = await withHttp(() => repo().refreshSession(),
          (req) => _json({'result': 'Unauthorized'}, 401));
      expect(res, RefreshStatus.expired);
      await AuthRepo.clearLocalSession();
      expect(prefs.getString(StorageKeys.REFRESH_TOKEN), isNull);
    });

    test('server error: failed, old token kept', () async {
      await prefs.setString(StorageKeys.REFRESH_TOKEN, 'tok-old');
      final res = await withHttp(
          () => repo().refreshSession(), (req) => http.Response('oops', 502));
      expect(res, RefreshStatus.failed);
      expect(prefs.getString(StorageKeys.REFRESH_TOKEN), 'tok-old');
    });

    test('logout during the call wins over the refreshed token', () async {
      await prefs.setString(StorageKeys.REFRESH_TOKEN, 'tok-old');
      final res = await withHttp(() => repo().refreshSession(), (req) {
        prefs.remove(StorageKeys.REFRESH_TOKEN);
        return _json({'errors': false, 'result': _session('tok-new')});
      });
      expect(res, RefreshStatus.noSession);
      expect(prefs.getString(StorageKeys.REFRESH_TOKEN), isNull);
    });
  });

  group('app-wake call push fields (mobile_platform / mobile_voip_token)', () {
    AuthRepo iosRepo() => AuthRepo(
        pushTokenProvider: () async => 'fcm-1',
        callPushFieldsProvider: () async =>
            {'mobile_platform': 'ios', 'mobile_voip_token': 'ab' * 32});

    test('login sends them next to mobile_device_id', () async {
      final res = await withHttp(
          () => iosRepo().loginUser('user@example.com', 's3cret'), (req) {
        final body = jsonDecode(req.body);
        expect(body['mobile_device_id'], 'fcm-1');
        expect(body['mobile_platform'], 'ios');
        expect(body['mobile_voip_token'], 'ab' * 32);
        return _json({'errors': false, 'result': _session('tok-A')});
      });
      expect(res, isTrue);
    });

    test('2FA verify sends them too', () async {
      final challenge = MfaChallenge(
          tempToken: 'tmp',
          methods: const ['totp'],
          expiresAt: DateTime.now().add(const Duration(minutes: 5)),
          email: 'user@example.com',
          pushToken: 'fcm-1');
      final res = await withHttp(() => iosRepo().verifyMfaCode(challenge, '123456'), (req) {
        final body = jsonDecode(req.body);
        expect(body['code'], '123456');
        expect(body['mobile_platform'], 'ios');
        expect(body['mobile_voip_token'], 'ab' * 32);
        return _json({'errors': false, 'result': _session('tok-B')});
      });
      expect(res, isTrue);
    });

    test('refresh carries them as query parameters', () async {
      await prefs.setString(StorageKeys.REFRESH_TOKEN, 'tok-old');
      final res = await withHttp(() => iosRepo().refreshSession(), (req) {
        expect(req.url.path, Uri.parse(Endpoints.REFRESH_TOKEN_URL).path);
        expect(req.url.queryParameters['mobile_platform'], 'ios');
        expect(req.url.queryParameters['mobile_voip_token'], 'ab' * 32);
        return _json({'errors': false, 'result': _session('tok-new')});
      });
      expect(res, RefreshStatus.ok);
    });

    test('android sends the platform only', () async {
      final repo = AuthRepo(
          pushTokenProvider: () async => 'fcm-1',
          callPushFieldsProvider: () async => {'mobile_platform': 'android'});
      await withHttp(() => repo.loginUser('user@example.com', 's3cret'), (req) {
        final body = jsonDecode(req.body);
        expect(body['mobile_platform'], 'android');
        expect(body.containsKey('mobile_voip_token'), isFalse);
        return _json({'errors': false, 'result': _session('tok-A')});
      });
    });
  });

  group('SSO', () {
    test('trades the SSO token at /auth/refresh with the push token', () async {
      final res = await withHttp(() => repo().loginWithSsoToken('sso-jwt'), (req) {
        expect(req.url.path, Uri.parse(Endpoints.REFRESH_TOKEN_URL).path);
        expect(req.url.queryParameters['mobile_device_id'], 'fcm-1');
        expect(req.headers['Authorization'], 'Bearer sso-jwt');
        return _json({'errors': false, 'result': _session('tok-sso')});
      });
      expect(res, isTrue);
      expect(prefs.getString(StorageKeys.REFRESH_TOKEN), 'tok-sso');
      expect(prefs.getString(StorageKeys.ACCESS_TOKEN), 'tok-sso');
      expect(prefs.getString(StorageKeys.EMAIL), isNull);
    });
  });

  group('SessionKeeper', () {
    test('concurrent refreshes share one call', () async {
      var calls = 0;
      final keeper = SessionKeeper(
        refresh: () async {
          calls++;
          await Future<void>.delayed(const Duration(milliseconds: 10));
          return RefreshStatus.ok;
        },
        onExpired: () async {},
      );
      final r = await Future.wait([keeper.refreshNow(), keeper.refreshNow()]);
      expect(r, [RefreshStatus.ok, RefreshStatus.ok]);
      expect(calls, 1);
    });

    test('expired while running stops and calls onExpired', () async {
      var expired = 0;
      final keeper = SessionKeeper(
        refresh: () async => RefreshStatus.expired,
        onExpired: () async => expired++,
      );
      keeper.start();
      expect(keeper.isRunning, isTrue);
      await keeper.refreshNow();
      expect(expired, 1);
      expect(keeper.isRunning, isFalse);
    });

    test('network failure keeps running', () async {
      final keeper = SessionKeeper(
        refresh: () async => RefreshStatus.failed,
        onExpired: () async => fail('not expired'),
      );
      keeper.start();
      await keeper.refreshNow();
      expect(keeper.isRunning, isTrue);
      keeper.stop();
    });
  });
}
