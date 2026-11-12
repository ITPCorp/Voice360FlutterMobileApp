class StorageKeys {
  static String REFRESH_TOKEN = "refresh_token";
  static String ACCESS_TOKEN = "access_token";
  static String APPUSER_DATA = "user_data";
  /// "Remember me" checkbox state. The login itself is in the secure store
  /// (services/saved_login.dart).
  static String REMEMBER = "remember";
  /// Last email used for password sign-in, only to prefill the login field.
  static String EMAIL = "email";
  /// Legacy: 2.1.9 and older kept the "Remember me" password here in plain
  /// text. Never written now; SavedLogin.migrateLegacy moves it into the
  /// secure store and deletes it.
  static String PASSWORD = "password";
  static String DEVICE = "device";
  static String API_ID = "api_id";
  static String REALM = "realm";
  static String USER_ID = "user_id";
  static String EXTENTION = "extention";
  static String DEFAULT_NUMBER = "default_number";
  static String CURRENT_CALL_NUMBER = "current_call_number";
  static String CURRENT_CALL_NAME = "current_call_name";
  static String DARK_THEME = "dark_theme";
  static String TIME_ZONE = "time_zone";
}
