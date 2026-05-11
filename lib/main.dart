import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:get/get.dart';
import 'package:itp_voice/cache/cache_service.dart';
import 'package:itp_voice/controllers/bindings.dart';
import 'package:itp_voice/design/v360.dart';
import 'package:itp_voice/locator.dart';
import 'package:itp_voice/notification_service.dart';
import 'package:itp_voice/routes.dart';
import 'package:timezone/data/latest_all.dart';

Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // ignore: avoid_print
  print('Handling a background message ${message.messageId}');
}

// Firebase options match the values in android/app/google-services.json (and
// the iOS GoogleService-Info.plist). Hard-coded so we don't rely on the
// google-services Gradle plugin's runtime resource merging which has been
// flaky on AGP 8.x.
const FirebaseOptions _kFirebaseOptions = FirebaseOptions(
  apiKey: 'AIzaSyCCAq0MQoIL_cjOaoNCKv3hRhYBv5DQ_xI',
  appId: '1:876937112371:android:1f308b6fb95f064892ec46',
  messagingSenderId: '876937112371',
  projectId: 'itpvoice-9ea83',
  storageBucket: 'itpvoice-9ea83.appspot.com',
);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Open the persistent SWR cache before anything else needs to read it.
  // Failure is non-fatal — controllers will simply not have warm data.
  try {
    await AppCache.instance.init();
  } catch (e) {
    // ignore: avoid_print
    print('AppCache init failed: $e');
  }

  try {
    // On Android, Firebase typically auto-initializes via the
    // FirebaseInitProvider when google-services.json is present. If that
    // succeeded, Firebase.apps will already contain [DEFAULT]. Otherwise,
    // initialize manually with explicit options.
    if (Firebase.apps.isEmpty) {
      await Firebase.initializeApp(options: _kFirebaseOptions);
    }
    FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
  } catch (e, st) {
    // Firebase setup is non-fatal — calls and SMS still work without push.
    // ignore: avoid_print
    print('Firebase init failed: $e\n$st');
  }
  setupLocator();
  LocalNotificationService.initialize();
  initializeTimeZones();
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);
  runApp(const Voice360App());
}

class Voice360App extends StatelessWidget {
  const Voice360App({super.key});

  @override
  Widget build(BuildContext context) {
    return ScreenUtilInit(
      designSize: const Size(393, 786),
      minTextAdapt: true,
      builder: (context, _) => GetMaterialApp(
        title: 'VOICE360',
        initialBinding: Binding(),
        theme: V360Theme.light(),
        darkTheme: V360Theme.dark(),
        themeMode: ThemeMode.system,
        debugShowCheckedModeBanner: false,
        getPages: AppRoutes.routes,
        initialRoute: Routes.LOGIN_SCREEN_ROUTE,
      ),
    );
  }
}
