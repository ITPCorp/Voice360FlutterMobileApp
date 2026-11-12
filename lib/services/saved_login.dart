import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:itp_voice/storage_keys.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Email + password kept for "Remember me" (#53034).
class SavedCredentials {
  final String email;
  final String password;
  const SavedCredentials(this.email, this.password);
}

/// The "Remember me" sign-in, kept in the platform secure store (iOS
/// Keychain, Android Keystore) instead of SharedPreferences.
///
/// The app first renews the session with /auth/refresh; when the token has
/// expired anyway (24 h) it signs in again with this saved login, the way
/// 2.1.9 did, so a phone never asks for the password again. A 2FA contact
/// is asked for the 6-digit code only.
class SavedLogin {
  SavedLogin({FlutterSecureStorage? storage})
      : _storage = storage ??
            const FlutterSecureStorage(
              // Readable after the first unlock, so a push that wakes the
              // app in the background can still renew the session.
              iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock),
            );

  final FlutterSecureStorage _storage;

  static const String _kEmail = 'v360_saved_login_email';
  static const String _kPassword = 'v360_saved_login_password';

  Future<void> save(String email, String password) async {
    await _storage.write(key: _kEmail, value: email);
    await _storage.write(key: _kPassword, value: password);
  }

  Future<SavedCredentials?> read() async {
    try {
      final email = await _storage.read(key: _kEmail);
      final password = await _storage.read(key: _kPassword);
      if (email == null || email.isEmpty || password == null || password.isEmpty) {
        return null;
      }
      return SavedCredentials(email, password);
    } catch (_) {
      return null;
    }
  }

  Future<void> clear() async {
    try {
      await _storage.delete(key: _kPassword);
      await _storage.delete(key: _kEmail);
    } catch (_) {}
  }

  /// Builds up to 2.1.9 kept the "Remember me" password in plain
  /// SharedPreferences. Move it into the secure store and delete the plain
  /// copy. Nobody is signed out: the session token is not touched, and the
  /// saved login keeps working from the secure store. If the secure store
  /// cannot be written, the plain copy stays and the next start retries.
  Future<void> migrateLegacy(SharedPreferences prefs) async {
    final password = prefs.get(StorageKeys.PASSWORD);
    if (password is! String || password.isEmpty) {
      if (password != null) await prefs.remove(StorageKeys.PASSWORD);
      return;
    }
    final email = prefs.get(StorageKeys.EMAIL);
    final remember = prefs.get(StorageKeys.REMEMBER);
    if (remember == true && email is String && email.isNotEmpty) {
      try {
        await save(email, password);
      } catch (_) {
        return;
      }
    }
    await prefs.remove(StorageKeys.PASSWORD);
  }
}
