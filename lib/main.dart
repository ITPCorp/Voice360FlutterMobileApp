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

  // Open the persistent SWR cache before anything else needs to read it.
  // Failure is non-fatal — controllers will simply not have warm data.
  try {
    await AppCache.instance.init();
  } catch (e) {
    // ignore: avoid_print
    print('AppCache init failed: $e');
  }

  // Firebase init pattern (cross-platform):
  //   1. Android: `google-services` Gradle plugin embeds a content provider
  //      that registers the [DEFAULT] FirebaseApp before main() runs.
  //   2. iOS: the FlutterFire native iOS module reads
  //      `ios/Runner/GoogleService-Info.plist` and registers similarly.
  //   3. Native init can race with our Dart-side calls, so we:
  //        a. Try Firebase.app() first. If it returns, we're done.
  //        b. Otherwise call initializeApp. If THAT throws "already exists",
  //           native won the race — still a success. Probe again to confirm.
  //        c. firebaseReady only flips true after Firebase.app() returns
  //           something usable.
  Object? lastErr;
  for (var attempt = 0; attempt < 2; attempt++) {
    try {
      Firebase.app();
      // ignore: avoid_print
      print('[Firebase] Default app available (attempt ${attempt + 1})');
      firebaseReady = true;
      break;
    } catch (probeErr) {
      lastErr = probeErr;
      try {
        await Firebase.initializeApp(options: _kFirebaseOptions);
        // ignore: avoid_print
        print('[Firebase] initializeApp succeeded');
      } catch (initErr) {
        lastErr = initErr;
        final msg = initErr.toString().toLowerCase();
        if (!msg.contains('already exists')) {
          // ignore: avoid_print
          print('[Firebase] initializeApp failed: $initErr');
        }
      }
    }
  }
  if (!firebaseReady) {
    // ignore: avoid_print
    print('[Firebase] gave up — no [DEFAULT] app. Last error: $lastErr');
  } else {
    try {
      FirebaseMessaging.onBackgroundMessage(
          _firebaseMessagingBackgroundHandler);
    } catch (e) {
      // ignore: avoid_print
      print('[Firebase] onBackgroundMessage register failed: $e');
    }
  }
  setupLocator();
  // PushService owns the FCM pipeline: foreground banners, taps, deep-links,
  // plus the local-notifications channel setup. Fire-and-forget.
  unawaited(locator<PushService>().initialize());
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
