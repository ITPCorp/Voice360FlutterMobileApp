import 'dart:async';

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
import 'package:itp_voice/routes.dart';
import 'package:itp_voice/services/demo_mode_service.dart';
import 'package:itp_voice/services/push_service.dart';
import 'package:timezone/data/latest_all.dart';

Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // ignore: avoid_print
  print('Handling a background message ${message.messageId}');
}

/// True once `Firebase.initializeApp` has succeeded for this process.
/// Every Dart-side touch of FirebaseMessaging/FirebaseAuth/Firestore must
/// gate on this, otherwise `[core/no-app]` will throw on iOS where we
/// intentionally skip init until a GoogleService-Info.plist is present.
bool firebaseReady = false;

// Firebase options match android/app/google-services.json (Android) and
// ios/Runner/GoogleService-Info.plist (iOS). Hard-coded as a fallback so
// we don't rely on the google-services Gradle plugin's runtime resource
// merging (flaky on AGP 8.x).
const FirebaseOptions _kFirebaseOptions = FirebaseOptions(
  apiKey: 'AIzaSyAwmhPKLNseEmT7AwTsya5jNyDSlq-Tzp8',
  appId: '1:978411142854:android:322d5f317d4945392821c7',
  messagingSenderId: '978411142854',
  projectId: 'voice360mobile',
  storageBucket: 'voice360mobile.firebasestorage.app',
);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // CRITICAL: get to runApp() as fast as possible so the user sees the
  // purple splash screen instead of a white void. Every heavy bootstrap
  // step that used to live here (cache open, Firebase init, FCM listener
  // wiring, demo-mode load, orientation lock) is now fire-and-forget — the
  // LoginController already has a 3-second startup delay before deciding
  // whether to auto-route, which absorbs any of these completing late.
  // Previously a slow disk / slow Firebase init could keep main() blocking
  // for 10+ seconds, during which users saw a white screen and assumed
  // the app had crashed.
  setupLocator();
  unawaited(_bootstrapInBackground());
  runApp(const Voice360App());
}

Future<void> _bootstrapInBackground() async {
  // SWR cache — controllers will read empty until this finishes, which is
  // fine because they all re-fetch on screen mount.
  unawaited(() async {
    try {
      await AppCache.instance.init();
    } catch (e) {
      // ignore: avoid_print
      print('AppCache init failed: $e');
    }
  }());

  // Firebase: prefer the existing native-init app (Android's
  // google-services content provider / iOS's FlutterFire native module).
  // Fall back to Dart-side initializeApp ONLY if no [DEFAULT] app exists.
  // The retry loop is intentionally bounded — if it never wires up, push
  // notifications won't work but the rest of the app (SIP/SMS/calls)
  // doesn't depend on Firebase at all.
  try {
    Firebase.app();
    firebaseReady = true;
    // ignore: avoid_print
    print('[Firebase] Default app available (native init)');
  } catch (_) {
    try {
      await Firebase.initializeApp(options: _kFirebaseOptions);
      firebaseReady = true;
      // ignore: avoid_print
      print('[Firebase] initializeApp succeeded');
    } catch (initErr) {
      final msg = initErr.toString().toLowerCase();
      if (msg.contains('already exists')) {
        // Native init won the race after our probe — try once more.
        try {
          Firebase.app();
          firebaseReady = true;
        } catch (_) {}
      } else {
        // ignore: avoid_print
        print('[Firebase] init failed: $initErr');
      }
    }
  }
  if (firebaseReady) {
    try {
      FirebaseMessaging.onBackgroundMessage(
          _firebaseMessagingBackgroundHandler);
    } catch (e) {
      // ignore: avoid_print
      print('[Firebase] onBackgroundMessage register failed: $e');
    }
  }

  // Demo-mode pref + push pipeline + timezones — all fire-and-forget.
  try {
    await DemoModeService.instance.load();
  } catch (_) {}
  unawaited(locator<PushService>().initialize());
  try {
    initializeTimeZones();
  } catch (_) {}
  try {
    await SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);
  } catch (_) {}
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
