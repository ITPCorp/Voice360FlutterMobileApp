import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:itp_voice/models/get_devices_reponse_model/devices.dart';
import 'package:itp_voice/models/get_devices_reponse_model/get_devices_reponse_model.dart';
import 'package:itp_voice/models/login_reponse_model/app_user.dart';
import 'package:itp_voice/models/login_request_model.dart';
import 'package:itp_voice/models/services_response_model/service.dart';
import 'package:itp_voice/models/services_response_model/services_response_model.dart';
import 'package:itp_voice/models/user_profile_model/user_profile.dart';
import 'package:itp_voice/locator.dart';
import 'package:itp_voice/repo/base_requester.dart';
import 'package:itp_voice/repo/shares_preference_repo.dart';
import 'package:itp_voice/routes.dart';
import 'package:itp_voice/services/global_socket_service.dart';
import 'package:itp_voice/services/push_service.dart';
import 'package:itp_voice/services/session_keeper.dart';
import 'package:itp_voice/storage_keys.dart';
import 'package:shared_preferences/shared_preferences.dart';


class AuthRepo {
//   Future getAllPosts() async {
//     http.Response response;
//     try {
//       response = await http.get(
//         Uri.parse(
//             "https://accounts.accesscontrol.windows.net/46b48e7d-06a1-4f29-870a-d5cffc2c8e14/tokens/oAuth/2"),
//         headers: <String, String>{
//           'Content-Type': 'application/json; charset=UTF-8',
//           'grant_type': 'client_credentials',
//           'client_id':
//               '38947a19-eb00-49f8-acaa-3afa9d2a0755@46b48e7d-06a1-4f29-870a-d5cffc2c8e14',
//           'client_secret': 'PI71DmpnA+QF7K4F0M3mnqN9fgeW1ep2ZYfyV1Hp/l4=',
//           'resource':
//               '00000003-0000-0ff1-ce00-000000000000/martindowgroup.sharepoint.com@46b48e7d-06a1-4f29-870a-d5cffc2c8e14'
//         },
//       );

//       if (response.statusCode == 200) {
//         print(response.body);
//         return response.body;
//       } else {
//         return response.statusCode;
//       }
//     } catch (e) {
//       print(e.toString());

//       return null;
//     }
//   }

//   Future<List?> getPosts() async {
//     print('Remote Service Class');

//     //var client = http.Client();

//     final uri = Uri.parse(
//         'https://accounts.accesscontrol.windows.net/46b48e7d-06a1-4f29-870a-d5cffc2c8e14/tokens/oAuth/2');
//     final request = http.Request('GET', uri);
//     //request.body = '{"grant_type":client_credentials,"client_id":38947a19-eb00-49f8-acaa-3afa9d2a0755@46b48e7d-06a1-4f29-870a-d5cffc2c8e14,"client_secret":PI71DmpnA+QF7K4F0M3mnqN9fgeW1ep2ZYfyV1Hp/l4=,"resource":00000003-0000-0ff1-ce00-000000000000/martindowgroup.sharepoint.com@46b48e7d-06a1-4f29-870a-d5cffc2c8e14}' ;

//     final query_parameters = {
//       'grant_type': 'client_credentials',
//       'client_id':
//           '38947a19-eb00-49f8-acaa-3afa9d2a0755@46b48e7d-06a1-4f29-870a-d5cffc2c8e14',
//       'client_secret': 'PI71DmpnA+QF7K4F0M3mnqN9fgeW1ep2ZYfyV1Hp/l4=',
//       'resource':
//           '00000003-0000-0ff1-ce00-000000000000/martindowgroup.sharepoint.com@46b48e7d-06a1-4f29-870a-d5cffc2c8e14'
//     };
//     print('data');

//     final sal_uri = Uri.https(
//         'accounts.accesscontrol.windows.net',
//         '46b48e7d-06a1-4f29-870a-d5cffc2c8e14/tokens/oAuth/2',
//         query_parameters);
//     http.Response response3 = await http.get(sal_uri);

//     print('--------------after response: ${response3.statusCode}');
//     // String body = json.encode(data);
//     // print('json convert: ${body}');

// /*    http.Response response = http.post(Uri.https('accounts.accesscontrol.windows.net', '46b48e7d-06a1-4f29-870a-d5cffc2c8e14/tokens/oAuth/2'),
//       body: data
//     );*/

//     final response2 = await request.send().asStream().first;

//     print(response2.toString());
//     //print('--------------- response 2 status code: ${response2.statusCode}');

//     // final response = await http.get(uri, headers: {
//     //   'Content-Type': 'application/json'
//     // });
//     //Map<dynamic,String> headers = {HttpHeaders.contentTypeHeader:'application/json','Accept':'application/json;odata=verbose'};

//     // http.Response response = await http.post(uri,
//     //     body: {
//     //       'grant_type':'client_credentials',
//     //       'client_id':'38947a19-eb00-49f8-acaa-3afa9d2a0755@46b48e7d-06a1-4f29-870a-d5cffc2c8e14',
//     //       'client_secret':'PI71DmpnA+QF7K4F0M3mnqN9fgeW1ep2ZYfyV1Hp/l4=',
//     //       'resource':'00000003-0000-0ff1-ce00-000000000000/martindowgroup.sharepoint.com@46b48e7d-06a1-4f29-870a-d5cffc2c8e14',
//     //
//     //     });

//     // print('------------- status code: ${response.statusCode}');

//     // var response = await client.get(uri,body:
//     // {
//     // 'grant_type':'client_credentials',
//     // 'client_id':'38947a19-eb00-49f8-acaa-3afa9d2a0755@46b48e7d-06a1-4f29-870a-d5cffc2c8e14',
//     // 'client_secret':'PI71DmpnA+QF7K4F0M3mnqN9fgeW1ep2ZYfyV1Hp/l4=',
//     // 'resource':'00000003-0000-0ff1-ce00-000000000000/martindowgroup.sharepoint.com@46b48e7d-06a1-4f29-870a-d5cffc2c8e14',
//     //
//     // } );

//     // try{
//     //   if(response.statusCode==200)
//     //   {
//     //     var json = response2.body;
//     //     print('remote service Authentication Success');
//     //     print(response.toString());
//     //     return postsModalFromJson(json).toList();
//     //   }
//     //   else{
//     //     const Text('The server is not responding.');
//     //   }
//     // }
//     // catch(e){
//     //   print('Salman  $e');
//     // }
//   }

///////////

  /// Builds the FCM token sent as `mobile_device_id`. Injectable so unit
  /// tests do not touch Firebase.
  final Future<String?> Function() _pushToken;

  AuthRepo({Future<String?> Function()? pushTokenProvider})
      : _pushToken = pushTokenProvider ??
            (() => locator<PushService>().onLoginSuccess());

  /// Older builds saved the plaintext password (and a "remember me" flag that
  /// only controlled that) in SharedPreferences. Delete both on every start.
  /// The email stays: it only prefills the sign-in field.
  static Future<void> purgeLegacyCredentials(SharedPreferences prefs) async {
    await prefs.remove(StorageKeys.PASSWORD);
    await prefs.remove(StorageKeys.REMEMBER);
  }

  /// Password sign-in, step 1.
  ///
  /// Returns `true` when signed in, an [MfaChallenge] when the contact has
  /// two-factor on (call [verifyMfaCode] next), or a String error message.
  Future<dynamic> loginUser(String email, String password) async {
    final Map<String, dynamic> loginBody =
        LoginRequestModel(username: email, password: password).toMap();
    // Push registration: request OS permission, fetch current FCM token, and
    // send it to the backend so it can target this device for SMS/call pushes.
    final pushToken = await _safePushToken();
    if (pushToken != null) {
      loginBody['mobile_device_id'] = pushToken;
    }
    final res = await _send('POST', Endpoints.LOGIN_URL, body: loginBody);
    if (res == null) {
      return "Couldn't reach the server. Check your connection and try again.";
    }
    final data = res.body;
    if (res.status == 429) {
      return _message(data) ?? 'Too many login attempts. Please try again later.';
    }
    if (res.status != 200 || data == null || data['errors'] == true) {
      return _message(data) ?? 'Invalid credentials';
    }
    final result = data['result'];
    if (result is! Map) return 'Something went wrong';
    final challenge = MfaChallenge.fromResult(
        Map<String, dynamic>.from(result), email: email, pushToken: pushToken);
    if (challenge != null) return challenge;
    return _finishSession(Map<String, dynamic>.from(result), email: email);
  }

  /// Password sign-in, step 2 (only when [loginUser] returned a challenge).
  ///
  /// Returns `true` when signed in, otherwise an [AuthFailure]. When
  /// [AuthFailure.restart] is set the temp token is gone and the user has to
  /// enter the password again.
  Future<dynamic> verifyMfaCode(MfaChallenge challenge, String code) async {
    if (challenge.isExpired) {
      return const AuthFailure('Invalid or expired sign-in. Start again.',
          restart: true);
    }
    final body = <String, dynamic>{'code': code};
    if (challenge.pushToken != null) {
      body['mobile_device_id'] = challenge.pushToken;
    }
    final res = await _send('POST', Endpoints.VERIFY_2FA_URL,
        body: body, bearer: challenge.tempToken);
    if (res == null) {
      return const AuthFailure(
          "Couldn't reach the server. Check your connection and try again.");
    }
    final data = res.body;
    if (res.status == 200 && data != null && data['errors'] != true) {
      final result = data['result'];
      if (result is! Map) return const AuthFailure('Something went wrong');
      final done =
          await _finishSession(Map<String, dynamic>.from(result), email: challenge.email);
      return done == true ? true : AuthFailure(done.toString());
    }
    if (res.status == 429) {
      return AuthFailure(_message(data) ?? 'Too many attempts. Try again later.');
    }
    final message = _message(data) ?? 'Invalid code';
    // "Invalid or expired sign-in. Start again." means the temp token is dead.
    final restart = message.toLowerCase().contains('start again');
    return AuthFailure(message, restart: restart);
  }

  /// Sign in via an SSO bearer token returned from the OAuth callback URL
  /// (`itpvoice://login?token=<jwt>`).
  ///
  /// The token is a portal-scoped JWT. Trade it at `/portal/crm/auth/refresh`
  /// (the same call [refreshSession] makes), which returns the full login
  /// body. From there we run the same chain as email/password login.
  Future<dynamic> loginWithSsoToken(String ssoToken) async {
    try {
      final pushToken = await _safePushToken();
      final res = await _requestRefresh(ssoToken, pushToken: pushToken);
      if (res == null) {
        return 'Could not complete sign-in. Please try again.';
      }
      final data = res.body;
      if (res.status != 200 || data == null || data['errors'] == true) {
        return _message(data) ?? 'Sign-in failed.';
      }
      // Tolerate the user object at the top level as well as under `result`.
      final result = data['result'] ?? data;
      if (result is! Map) return 'Could not complete sign-in. Please try again.';
      return await _finishSession(Map<String, dynamic>.from(result), email: null);
    } catch (e) {
      print('SSO login error: $e');
      await SharedPreferencesMethod.storage.remove(StorageKeys.REFRESH_TOKEN);
      return 'Sign-in failed. Please try again.';
    }
  }

  /// Trade the stored session token for a fresh one (tokens last 24 h, the
  /// server refreshes any token that has not expired yet).
  ///
  /// [RefreshStatus.expired] means the server said 401: the session is over
  /// and the user must sign in. [RefreshStatus.failed] is a network or server
  /// error; the stored token is kept and the caller retries later.
  Future<RefreshStatus> refreshSession() async {
    final sent = SharedPreferencesMethod.getString(StorageKeys.REFRESH_TOKEN);
    if (sent == null || sent.isEmpty) return RefreshStatus.noSession;
    final res = await _requestRefresh(sent);
    // A logout or a new login while the call was in flight wins.
    final current = SharedPreferencesMethod.getString(StorageKeys.REFRESH_TOKEN);
    if (current != sent) {
      return (current == null || current.isEmpty)
          ? RefreshStatus.noSession
          : RefreshStatus.ok;
    }
    if (res == null) return RefreshStatus.failed;
    if (res.status == 401) return RefreshStatus.expired;
    final data = res.body;
    if (res.status != 200 || data == null || data['errors'] == true) {
      return RefreshStatus.failed;
    }
    final result = data['result'];
    if (result is! Map) return RefreshStatus.failed;
    final user = AppUser.fromMap(Map<String, dynamic>.from(result));
    final access = user.accessToken;
    final refresh = user.refreshToken;
    if (access == null || access.isEmpty || refresh == null || refresh.isEmpty) {
      return RefreshStatus.failed;
    }
    await SharedPreferencesMethod.storage.setString(StorageKeys.REFRESH_TOKEN, refresh);
    await SharedPreferencesMethod.storage.setString(StorageKeys.ACCESS_TOKEN, access);
    if (user.timeZone != null) {
      await SharedPreferencesMethod.storage.setString(StorageKeys.TIME_ZONE, user.timeZone!);
    }
    await SharedPreferencesMethod.storage
        .setString(StorageKeys.APPUSER_DATA, json.encode(user.toMap()));
    return RefreshStatus.ok;
  }

  /// Drop the local session without calling the server (used when the
  /// server already said the token is dead). Keeps the email for prefill.
  static Future<void> clearLocalSession() async {
    await SharedPreferencesMethod.storage.remove(StorageKeys.ACCESS_TOKEN);
    await SharedPreferencesMethod.storage.remove(StorageKeys.REFRESH_TOKEN);
    await SharedPreferencesMethod.storage.remove(StorageKeys.APPUSER_DATA);
    await SharedPreferencesMethod.storage.remove(StorageKeys.TIME_ZONE);
  }

  Future<_AuthResponse?> _requestRefresh(String bearer, {String? pushToken}) {
    var url = Endpoints.REFRESH_TOKEN_URL;
    if (pushToken != null && pushToken.isNotEmpty) {
      url = '$url?mobile_device_id=${Uri.encodeQueryComponent(pushToken)}';
    }
    return _send('GET', url, bearer: bearer);
  }

  /// Shared tail of every sign-in (password, password + code, SSO): store the
  /// session, then load services, realm, device and user id.
  Future<dynamic> _finishSession(Map<String, dynamic> result,
      {required String? email}) async {
    try {
      final user = AppUser.fromMap(result);
      final access = user.accessToken;
      final refresh = user.refreshToken;
      if (access == null || access.isEmpty || refresh == null || refresh.isEmpty) {
        return 'Sign-in response was missing tokens.';
      }
      // BaseRequester sends REFRESH_TOKEN as the bearer, so the calls below need it.
      await SharedPreferencesMethod.storage.setString(StorageKeys.REFRESH_TOKEN, refresh);
      if (user.timeZone != null) {
        await SharedPreferencesMethod.storage.setString(StorageKeys.TIME_ZONE, user.timeZone!);
      }
      final devices = await getDevices();
      if (devices != true) {
        await SharedPreferencesMethod.storage.remove(StorageKeys.REFRESH_TOKEN);
        return devices is String ? devices : 'Something went wrong';
      }
      final userId = await getUserID();
      if (userId != true) {
        await SharedPreferencesMethod.storage.remove(StorageKeys.REFRESH_TOKEN);
        return userId is String ? userId : 'Something went wrong';
      }
      await SharedPreferencesMethod.storage.setString(StorageKeys.ACCESS_TOKEN, access);
      await purgeLegacyCredentials(SharedPreferencesMethod.storage);
      if (email != null && email.isNotEmpty) {
        await SharedPreferencesMethod.storage.setString(StorageKeys.EMAIL, email);
      } else {
        await SharedPreferencesMethod.storage.remove(StorageKeys.EMAIL);
      }
      await SharedPreferencesMethod.storage
          .setString(StorageKeys.APPUSER_DATA, json.encode(user.toMap()));
      SharedPreferencesMethod.getUserData();
      return true;
    } catch (e) {
      print('finish sign-in failed: $e');
      await SharedPreferencesMethod.storage.remove(StorageKeys.REFRESH_TOKEN);
      return 'Something went wrong';
    }
  }

  Future<String?> _safePushToken() async {
    try {
      final t = await _pushToken();
      return (t == null || t.isEmpty) ? null : t;
    } catch (_) {
      return null;
    }
  }

  /// Plain HTTP for the auth calls. BaseRequester is not used here because it
  /// turns any 401 into "session expired, log out", and these calls need the
  /// status and message (wrong password, wrong code, 429) themselves.
  /// Returns null on a network error.
  static Future<_AuthResponse?> _send(String method, String url,
      {Map<String, dynamic>? body, String? bearer}) async {
    final headers = <String, String>{
      'Content-Type': 'application/json; charset=UTF-8',
      if (bearer != null) 'Authorization': 'Bearer $bearer',
    };
    try {
      final uri = Uri.parse(url);
      final http.Response r = method == 'GET'
          ? await http.get(uri, headers: headers).timeout(_authTimeout)
          : await http
              .post(uri, headers: headers, body: jsonEncode(body ?? const {}))
              .timeout(_authTimeout);
      Map<String, dynamic>? decoded;
      try {
        final j = json.decode(r.body);
        if (j is Map) decoded = Map<String, dynamic>.from(j);
      } catch (_) {}
      return _AuthResponse(r.statusCode, decoded);
    } catch (e) {
      print('auth request failed: $e');
      return null;
    }
  }

  static const Duration _authTimeout = Duration(seconds: 30);

  static String? _message(Map<String, dynamic>? data) {
    final m = data?['message'];
    if (m is String && m.isNotEmpty) return m;
    final r = data?['result'];
    if (r is String && r.isNotEmpty) return r;
    return null;
  }

  logoutUser() async {
    try {
      locator<SessionKeeper>().stop();
    } catch (_) {}
    await SharedPreferencesMethod.storage.remove(StorageKeys.ACCESS_TOKEN);
    await SharedPreferencesMethod.storage.remove(StorageKeys.REFRESH_TOKEN);
    await SharedPreferencesMethod.storage.remove(StorageKeys.APPUSER_DATA);
    await SharedPreferencesMethod.storage.remove(StorageKeys.TIME_ZONE);
    try {
      await locator<GlobalSocketService>().disconnect();
    } catch (_) {}
    try {
      await locator<PushService>().onLogout();
    } catch (_) {}
    try {
      await BaseRequesterMethods.baseRequester.baseGetAPI(Endpoints.LOGOUT_URL);
    } catch (e) {
      print(e.toString());
    }
  }

  getRealm() async {
    print("''''========getRealm line 260 auth repo--'1---'");
    String? apiId = await SharedPreferencesMethod.getString(StorageKeys.API_ID);
    print("''''========getRealm line 260 auth repo--''2----'${apiId}'");

    final apiResponse = await BaseRequesterMethods.baseRequester.baseGetAPI(Endpoints.GET_ACCOUNT_DETAILS(apiId));
    print("''''========getRealm line 260 auth repo--''3----'${apiResponse}'");
    if (!apiResponse['errors']) {
      print("Realmmm"+apiResponse['result']['realm']);
      SharedPreferencesMethod.storage.setString(StorageKeys.REALM, apiResponse['result']['realm']);
      return true;
    } else {
      return apiResponse['message'];
    }
  }

  getUserID() async {
    String? apiId = await SharedPreferencesMethod.getString(StorageKeys.API_ID);
    print("I am API ID"+StorageKeys.API_ID);
    final apiResponse = await BaseRequesterMethods.baseRequester.baseGetAPI(Endpoints.GET_USER_DATA(apiId));
    print("I am API response"+apiResponse.toString());
    if (apiResponse['message'] == "User details") {
      SharedPreferencesMethod.storage.setString(StorageKeys.USER_ID, apiResponse['result']['pk'].toString());

      SharedPreferencesMethod.storage.setString(StorageKeys.EXTENTION, apiResponse['result']['presence_id'].toString());

      SharedPreferencesMethod.storage.setString(StorageKeys.DEFAULT_NUMBER,
          apiResponse['result']['voice_account']['default_outbound_callerid_number'].toString());
      print("USER ID : ${apiResponse['result']['pk']}");
      return true;
    } else {
      return apiResponse['message'];
    }
  }

  getServices() async {
    final apiResponse = await BaseRequesterMethods.baseRequester.baseGetAPI(Endpoints.SERVICES_URL);
    if (!apiResponse['errors']) {
      // try {} catch (e) {}
      ServicesResponseModel response = ServicesResponseModel.fromMap(apiResponse);
      try {
        // for(int i =0;i<response.message
        List<Services> itpVoiceServices =
            response.services!.where((element) => element.product!.itemType == "itp_voice").toList();
        if (itpVoiceServices.length > 1) {
          return itpVoiceServices;
        }
        if (itpVoiceServices.length == 1) {
          SharedPreferencesMethod.storage.setString(StorageKeys.API_ID, itpVoiceServices[0].apiId.toString());
          return true;
        }
      } catch (e) {
        return "Something went wrong";
      }
    } else {
      return apiResponse['message'];
    }
    // final apiResponse = await requester.baseGetAPI(E);
  }

  getDevices() async {
    print("''''========get devices line 314 auth repo--''1---''");
    final servicesApiResponse = await getServices();
    print("''''========get devices line 314 auth repo--''2----''");
    if (servicesApiResponse.runtimeType == String) {
      return servicesApiResponse;
    }
    if (servicesApiResponse) {
      print("''''========get devices line 314 auth repo--''3----'${servicesApiResponse}'");
      final realmApiResponse = await getRealm();
      print("''''========get devices line 314 auth repo--''333----''");
      if (realmApiResponse.runtimeType == String) {
        return realmApiResponse;
      } else {
        print("''''========get devices line 314 auth repo--'4---''");
        String? apiId = await SharedPreferencesMethod.getString(StorageKeys.API_ID);

        final apiResponse = await BaseRequesterMethods.baseRequester.baseGetAPI(Endpoints.GET_DEVICES_URL(apiId));
        if (!apiResponse['errors']) {
          GetDevicesReponseModel response = GetDevicesReponseModel.fromMap(apiResponse);
          try {
            Devices appPhone = response.devices!.firstWhere(
              (element) => element.deviceType == "app_phone",
            );
            SharedPreferencesMethod.setString(
              StorageKeys.DEVICE,
              json.encode(
                appPhone.toMap(),
              ),
            );
            return true;
          } on StateError catch (e) {
            return "No registered device found";
          }
        } else {
          return apiResponse['message'];
        }
      }
    }
  }

  getProfile() async {
    String? apiId = await SharedPreferencesMethod.getString(StorageKeys.API_ID);
    UserProfile? profile;
    final apiResponse = await BaseRequesterMethods.baseRequester.baseGetAPI(
      Endpoints.USER_PROFILE,
    );
    if (!apiResponse['errors']) {
      UserProfile reponse = UserProfile.fromMap(apiResponse);
      return reponse;
    } else {
      return apiResponse['message'];
    }
  }

  Future<List<String>> getChatNumbers() async {
    List<String> numbers = <String>[];
    String? apiId = await SharedPreferencesMethod.getString(StorageKeys.API_ID);
    if (apiId != null) {
      try {
        final apiResponse = await BaseRequesterMethods.baseRequester.baseGetAPI(Endpoints.GET_CHAT_NUMBERS_URL(apiId));
        if (apiResponse.runtimeType == 1.runtimeType) {
          throw (401);
        }
        if (!apiResponse['errors']) {
          for (var numberData in apiResponse["result"]) {
            numbers.add(numberData["number"]);
          }
        }
      } catch (e) {
        if (e.toString() == "401") {
          throw ("401");
        }
        null;
      }
    }
    print("NUMBERS: $numbers");

    return numbers;
  }
}

/// Result of [AuthRepo.refreshSession].
enum RefreshStatus {
  /// New token stored.
  ok,

  /// Server answered 401: the token expired or was revoked. Sign in again.
  expired,

  /// Network or server error. The stored token is kept; retry later.
  failed,

  /// No stored token (never signed in, or signed out meanwhile).
  noSession,
}

/// The server wants a two-factor code before it hands out a session.
class MfaChallenge {
  final String tempToken;
  final List<String> methods;
  final DateTime expiresAt;

  /// Email typed on the password step, saved for prefill once signed in.
  final String email;

  /// FCM token from the password step, sent again on verify.
  final String? pushToken;

  MfaChallenge({
    required this.tempToken,
    required this.methods,
    required this.expiresAt,
    required this.email,
    this.pushToken,
  });

  bool get isExpired => DateTime.now().isAfter(expiresAt);

  /// Null unless [result] is a `requires_mfa` answer from `/auth/login`.
  static MfaChallenge? fromResult(Map<String, dynamic> result,
      {required String email, String? pushToken}) {
    if (result['requires_mfa'] != true) return null;
    final temp = result['temp_token'];
    if (temp is! String || temp.isEmpty) return null;
    final seconds = result['expires_in'] is num
        ? (result['expires_in'] as num).toInt()
        : 600;
    final methods = (result['mfa_methods'] is List)
        ? (result['mfa_methods'] as List).map((e) => e.toString()).toList()
        : const <String>['totp'];
    return MfaChallenge(
      tempToken: temp,
      methods: methods,
      expiresAt: DateTime.now().add(Duration(seconds: seconds)),
      email: email,
      pushToken: pushToken,
    );
  }
}

/// A failed code step. [restart] = go back to the password step.
class AuthFailure {
  final String message;
  final bool restart;
  const AuthFailure(this.message, {this.restart = false});

  @override
  String toString() => message;
}

class _AuthResponse {
  final int status;
  final Map<String, dynamic>? body;
  _AuthResponse(this.status, this.body);
}
