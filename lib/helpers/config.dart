import 'package:country_pickers/country.dart';

class Config {
  /// Build-time backend switch. `--dart-define=V360_ENV=dev` points the whole
  /// app at the dev stack (dev CRM + dev voice API + dev Kamailio, account 61)
  /// so test builds never touch production. Anything else = production.
  static const String ENV = String.fromEnvironment('V360_ENV', defaultValue: 'prod');
  static bool get isDev => ENV == 'dev';

  static String BASE_URL_CRM = isDev
      ? "https://api.itpscorp.com/dev/portal/crm"
      : "https://api.itpscorp.com/portal/crm";

  /// Prefix for other /portal/ services (360 contacts).
  static String BASE_URL_PORTAL = isDev
      ? "https://api.itpscorp.com/dev/portal/"
      : "https://api.itpscorp.com/portal/";

  static String BASE_URL_DEV = "https://api.itpscorp.com/dev";
  static String BASE_URL_ITP_VOICE = isDev
      ? "https://api.itpscorp.com/dev/portal/itpvoice/v2/"
      : "https://api.itpscorp.com/portal/itpvoice/v2/";

  static String WEB_SOCKET_URL = isDev
      ? "wss://ws.dev.sip.itpvoice.net:5066"
      : "wss://ws.sip.itpvoice.net:5066";
}

class Helpers {
  static List<String> alphabet = [
    "a",
    "b",
    "c",
    "d",
    "e",
    "f",
    "g",
    "h",
    "i",
    "j",
    "k",
    "l",
    "m",
    "n",
    "o",
    "p",
    "q",
    "r",
    "s",
    "t",
    "u",
    "v",
    "w",
    "x",
    "y",
    "z"
  ];
}
