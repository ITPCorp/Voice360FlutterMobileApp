class StorageKeys {
  static String REFRESH_TOKEN = "refresh_token";
  static String ACCESS_TOKEN = "access_token";
  static String APPUSER_DATA = "user_data";
  /// Legacy: "remember me" flag. Read only to delete it (#52888).
  static String REMEMBER = "remember";
  /// Last email used for password sign-in, only to prefill the login field.
  static String EMAIL = "email";
  /// Legacy: builds before #52888 saved the plaintext password here. Never
  /// write it; AuthRepo.purgeLegacyCredentials deletes it on every start.
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
