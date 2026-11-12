import 'package:email_validator/email_validator.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_web_auth_2/flutter_web_auth_2.dart';
import 'package:get/get.dart';
import 'package:itp_voice/cache/cache_service.dart';
import 'package:itp_voice/helpers/config.dart';
import 'package:itp_voice/locator.dart';
import 'package:itp_voice/models/call_history_model.dart';
import 'package:itp_voice/models/get_contacts_reponse_model/contact_response.dart';
import 'package:itp_voice/models/get_contacts_reponse_model/get_contacts_reponse_model.dart';
import 'package:itp_voice/models/get_message_threads_response_model/get_message_threads_response_model.dart';
import 'package:itp_voice/models/get_voice_mails_response_model/get_voice_mails_response_model.dart';
import 'package:itp_voice/repo/auth_repo.dart';
import 'package:itp_voice/repo/call_history_repo.dart';
import 'package:itp_voice/repo/contacts_repo.dart';
import 'package:itp_voice/repo/messages_repo.dart';
import 'package:itp_voice/repo/voice_mails_repo.dart';
import 'package:itp_voice/routes.dart';
import 'package:itp_voice/services/numbers_service.dart';
import 'package:itp_voice/services/session_keeper.dart';
import 'package:itp_voice/storage_keys.dart';
import 'package:itp_voice/widgets/custom_toast.dart';
import 'package:shared_preferences/shared_preferences.dart';

class LoginController extends GetxController {
  TextEditingController passwordController = TextEditingController();
  TextEditingController emailController = TextEditingController();
  TextEditingController codeController = TextEditingController();
  final _authRepo = AuthRepo();

  RxBool showLogin = false.obs;
  RxBool isLoading = false.obs;
  RxString errorMessage = ''.obs;

  /// Set while the two-factor code step is on screen.
  final Rxn<MfaChallenge> mfaChallenge = Rxn<MfaChallenge>();

  Future<void> login() async {
    if (isLoading.value) return;
    errorMessage.value = '';

    final localError = _validateLocally();
    if (localError != null) {
      errorMessage.value = localError;
      CustomToast.showToast(localError, true);
      return;
    }

    isLoading.value = true;
    try {
      final res = await _authRepo.loginUser(
        emailController.text.trim(),
        passwordController.text,
      );

      if (res == true) {
        await _onSignedIn();
        return;
      }

      if (res is MfaChallenge) {
        codeController.clear();
        mfaChallenge.value = res;
        return;
      }

      // Anything else is a failure. The repo returns a String when the
      // server provides a message.
      final message = (res is String && res.isNotEmpty)
          ? _humanizeServerError(res)
          : 'Invalid email or password. Please try again.';
      errorMessage.value = message;
      CustomToast.showToast(message, true);
    } catch (e) {
      const message =
          'Couldn\'t reach the server. Check your connection and try again.';
      errorMessage.value = message;
      CustomToast.showToast(message, true);
    } finally {
      isLoading.value = false;
    }
  }

  /// Second sign-in step: the 6-digit code from the authenticator app.
  Future<void> verifyCode() async {
    final challenge = mfaChallenge.value;
    if (challenge == null || isLoading.value) return;
    final code = codeController.text.trim();
    if (!RegExp(r'^\d{6}$').hasMatch(code)) {
      errorMessage.value = 'Enter the 6-digit code from your authenticator app.';
      return;
    }
    errorMessage.value = '';
    isLoading.value = true;
    try {
      final res = await _authRepo.verifyMfaCode(challenge, code);
      if (res == true) {
        await _onSignedIn();
        return;
      }
      final failure = res is AuthFailure
          ? res
          : const AuthFailure('Something went wrong. Please try again.');
      codeController.clear();
      if (failure.restart) {
        mfaChallenge.value = null;
        errorMessage.value = 'Your sign-in timed out. Enter your password again.';
      } else {
        errorMessage.value = failure.message;
      }
      CustomToast.showToast(errorMessage.value, true);
    } catch (e) {
      const message =
          'Couldn\'t reach the server. Check your connection and try again.';
      errorMessage.value = message;
      CustomToast.showToast(message, true);
    } finally {
      isLoading.value = false;
    }
  }

  /// "Back to sign in" from the code step.
  void cancelMfa() {
    mfaChallenge.value = null;
    codeController.clear();
    errorMessage.value = '';
  }

  /// Common tail of every successful sign-in (password, code, SSO).
  Future<void> _onSignedIn() async {
    // Let the OS password manager offer to save what was typed. Runs before
    // the fields are cleared, since it reads them.
    try {
      TextInput.finishAutofillContext();
    } catch (_) {}
    mfaChallenge.value = null;
    passwordController.clear();
    codeController.clear();
    locator<SessionKeeper>().start();
    await locator<NumbersService>().getUpdatedNumbersList();
    // Kick off background warmup so the rest of the app feels instant.
    // Don't await, let routing happen immediately.
    _warmCachesInBackground();
    Get.offAllNamed(Routes.BASE_SCREEN_ROUTE);
  }

  /// Kick off Google or Microsoft OAuth via the portal backend.
  /// `provider` is 'google' or 'microsoft'.
  Future<void> loginWithSso(String provider) async {
    if (isLoading.value) return;
    errorMessage.value = '';
    isLoading.value = true;
    try {
      // The backend redirects to itpvoice://login?token=<jwt> on success
      // (or itpvoice://login?error=...&error_description=... on failure).
      final authUrl = '${Config.BASE_URL_CRM}/auth/$provider/login'
          '?redirect_url=itpvoice://login';
      final callback = await FlutterWebAuth2.authenticate(
        url: authUrl,
        callbackUrlScheme: 'itpvoice',
      );
      final callbackUri = Uri.parse(callback);
      final error = callbackUri.queryParameters['error'];
      if (error != null) {
        final desc = callbackUri.queryParameters['error_description'];
        final msg = desc ?? 'Sign-in with ${_providerLabel(provider)} failed.';
        errorMessage.value = msg;
        CustomToast.showToast(msg, true);
        return;
      }
      final token = callbackUri.queryParameters['token'];
      if (token == null || token.isEmpty) {
        const msg = 'Sign-in did not return a token. Please try again.';
        errorMessage.value = msg;
        CustomToast.showToast(msg, true);
        return;
      }

      final res = await _authRepo.loginWithSsoToken(token);
      if (res == true) {
        await _onSignedIn();
        return;
      }
      final message = (res is String && res.isNotEmpty)
          ? _humanizeServerError(res)
          : 'Sign-in failed. Please try again.';
      errorMessage.value = message;
      CustomToast.showToast(message, true);
    } catch (e) {
      // User cancellation throws a PlatformException("CANCELED"); treat it
      // as a silent no-op rather than a scary error.
      final s = e.toString().toLowerCase();
      if (s.contains('cancel') || s.contains('canceled')) {
        return;
      }
      const message = 'Could not start sign-in. Check your connection.';
      errorMessage.value = message;
      CustomToast.showToast(message, true);
    } finally {
      isLoading.value = false;
    }
  }

  String _providerLabel(String p) =>
      p == 'google' ? 'Google' : (p == 'microsoft' ? 'Microsoft' : p);

  String? _validateLocally() {
    final email = emailController.text.trim();
    final password = passwordController.text;
    if (email.isEmpty || password.isEmpty) {
      return 'Please enter your email and password.';
    }
    if (!EmailValidator.validate(email)) {
      return 'Please enter a valid email address.';
    }
    if (password.length < 4) {
      return 'Password must be at least 4 characters.';
    }
    return null;
  }

  /// Kick off parallel warmups for the main data sets after a successful
  /// login. Fire-and-forget — failures here don't block UX, the in-screen
  /// SWR pattern will retry on view-open.
  void _warmCachesInBackground() {
    Future.microtask(() async {
      try {
        final messagesRepo = MessagesRepo();
        final callsRepo = CallHistoryRepo();
        final voicemailsRepo = VoiceMailsRepo();
        final contactsRepo = ContactsRepo();
        final chatNumber = locator<NumbersService>().chatNumbers.isNotEmpty
            ? locator<NumbersService>().chatNumbers.first
            : '';

        // Don't await — these run concurrently. Each persists its own results
        // into AppCache on success.
        await Future.wait<void>([
          _warmContacts(contactsRepo),
          _warmThreads(messagesRepo, chatNumber),
          _warmCallHistory(callsRepo),
          _warmVoicemails(voicemailsRepo),
        ]);
      } catch (e) {
        // ignore: avoid_print
        print('Cache warmup failed: $e');
      }
    });
  }

  Future<void> _warmContacts(ContactsRepo repo) async {
    try {
      final res = await repo.getContacts('0');
      if (res is ContactResponse && res.result != null) {
        final fresh = res.result!
            .where((c) => (c.firstname != null && c.firstname!.isNotEmpty))
            .toList();
        if (AppCache.instance.isReady) {
          await AppCache.instance.contacts.writeAll(fresh);
        }
      }
    } catch (_) {}
  }

  Future<void> _warmThreads(MessagesRepo repo, String from) async {
    if (from.isEmpty) return;
    try {
      final res = await repo.getMessageThreads(from);
      if (res is GetMessageThreadsResponseModel) {
        final list = res.result?.messageThreads ?? const [];
        if (AppCache.instance.isReady) {
          await AppCache.instance.threads.write(from, list);
        }
      }
    } catch (_) {}
  }

  Future<void> _warmCallHistory(CallHistoryRepo repo) async {
    try {
      final res = await repo.fetchCallHistory(offSet: 0);
      if (res is List<CallHistory> && AppCache.instance.isReady) {
        await AppCache.instance.callHistory.writeAll(res);
      }
    } catch (_) {}
  }

  Future<void> _warmVoicemails(VoiceMailsRepo repo) async {
    try {
      final res = await repo.getVoiceMails();
      if (res is GetVoiceMailsResponseModel && AppCache.instance.isReady) {
        await AppCache.instance.voicemails.writeAll(res.voiceMails ?? const []);
      }
    } catch (_) {}
  }

  // Server errors are usually short ("invalid_credentials") or noisy
  // ("[object Object]" / raw JSON). Map the common ones; otherwise pass through
  // if it looks like a sentence.
  String _humanizeServerError(String raw) {
    final s = raw.trim();
    final lc = s.toLowerCase();
    if (lc.contains('invalid') &&
        (lc.contains('credential') || lc.contains('password') || lc.contains('login'))) {
      return 'Invalid email or password. Please try again.';
    }
    if (lc.contains('not found') || lc.contains('no user')) {
      return 'We couldn\'t find an account with that email.';
    }
    if (lc.contains('locked') || lc.contains('disabled')) {
      return 'This account is locked. Contact your administrator.';
    }
    if (lc.contains('timeout') || lc.contains('network')) {
      return 'Network error. Please try again.';
    }
    // Looks like a server-side sentence — show as-is.
    if (s.length < 160 && s.contains(' ')) return s;
    return 'Something went wrong. Please try again.';
  }

  bool initializedd = false;

  @override
  void onInit() {
    super.onInit();
    initializedd = false;
    // Upgrade from a build that saved the password: delete it now.
    SharedPreferences.getInstance()
        .then(AuthRepo.purgeLegacyCredentials)
        .catchError((_) {});
    Future.delayed(const Duration(seconds: 3), () async {
      SharedPreferences _prefs = await SharedPreferences.getInstance();
      await _applyStoredTheme(_prefs);
      String? token = _prefs.getString(StorageKeys.REFRESH_TOKEN);
      if (token == null || token.isEmpty) {
        _showLoginForm(_prefs);
        return;
      }
      // Trade the stored token for a fresh one before going in. A 401 means
      // it expired (24 h): back to the login form with the email filled in.
      // A network error keeps the token and goes in as before.
      final keeper = locator<SessionKeeper>();
      final status = await keeper.refreshNow();
      if (status == RefreshStatus.expired || status == RefreshStatus.noSession) {
        await AuthRepo.clearLocalSession();
        _showLoginForm(_prefs,
            message: status == RefreshStatus.expired
                ? 'Your session expired. Please sign in again.'
                : null);
        return;
      }
      try {
        await locator<NumbersService>().getUpdatedNumbersList();
      } catch (e) {
        showLogin.value = true;
        return;
      }
      keeper.start(fresh: status == RefreshStatus.ok);
      if (Get.currentRoute == Routes.LOGIN_SCREEN_ROUTE) {
        Get.offAllNamed(Routes.BASE_SCREEN_ROUTE);
      }
      initializedd = true;
      // Auto-login path: warm caches so the app feels instant when the user
      // navigates to any tab.
      _warmCachesInBackground();
    });
  }

  void _showLoginForm(SharedPreferences prefs, {String? message}) {
    final email = prefs.getString(StorageKeys.EMAIL);
    if (email != null && email.isNotEmpty && emailController.text.isEmpty) {
      emailController.text = email;
    }
    if (message != null) errorMessage.value = message;
    showLogin.value = true;
  }

  Future<void> _applyStoredTheme(SharedPreferences prefs) async {
    // DARK_THEME was historically stored as a bool; tolerate the legacy type.
    String? stored;
    try {
      stored = prefs.getString(StorageKeys.DARK_THEME);
    } catch (_) {
      await prefs.remove(StorageKeys.DARK_THEME);
      stored = null;
    }
    final mode = switch (stored) {
      'light' => ThemeMode.light,
      'dark' => ThemeMode.dark,
      _ => ThemeMode.system,
    };
    Get.changeThemeMode(mode);
  }
}
