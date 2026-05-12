import 'dart:async';
import 'dart:io' show Platform;

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
/// gate on this, otherwise `[core/no-app]` will throw.
bool firebaseReady = false;

// Android-only fallback if the google-services content provider didn't
// register the [DEFAULT] FirebaseApp before main() ran. NEVER pass these
// on iOS — the appId is the Android one, and Firebase rejects mismatched
// options against the already-iOS-registered app. (Shipped in 2.1.3 — was
// the suspected cause of the iOS release-mode hang reported by users.)
const FirebaseOptions _kAndroidFirebaseOptions = FirebaseOptions(
  apiKey: 'AIzaSyAwmhPKLNseEmT7AwTsya5jNyDSlq-Tzp8',
  appId: '1:978411142854:android:322d5f317d4945392821c7',
  messagingSenderId: '978411142854',
  projectId: 'voice360mobile',
  storageBucket: 'voice360mobile.firebasestorage.app',
);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // CRITICAL: get to runApp() as fast as possible. Every heavy bootstrap
  // step (cache open, Firebase init, FCM listener wiring, demo-mode load,
  // orientation lock) is fire-and-forget. The LoginController has a
  // 3-second startup delay before deciding whether to auto-route, which
  // absorbs the bootstrap window invisibly.
  //
  // 2.1.3 awaited all of this serially in main(), so a slow Firebase
  // init / mismatched options / slow disk could keep main() blocked
  // for 15+ minutes. Users saw a white screen (Android) or a frozen
  // launch image (iOS) and assumed the app had crashed.
  setupLocator();
  unawaited(_bootstrapInBackground());
  runApp(const Voice360App());
}

Future<void> _bootstrapInBackground() async {
  try {
    await AppCache.instance.init();
  } catch (e) {
    // ignore: avoid_print
    print('AppCache init failed: $e');
  }

  // Firebase: trust the native-init path on both platforms.
  //   * Android: `google-services` plugin embeds a content provider
  //     that registers [DEFAULT] before main() runs.
  //   * iOS: FlutterFire's native iOS module reads
  //     GoogleService-Info.plist and registers similarly.
  // Only Android has a Dart-side fallback; iOS would only get here if
  // native init genuinely failed, and our hardcoded options are Android's.
  try {
    Firebase.app();
    firebaseReady = true;
    // ignore: avoid_print
    print('[Firebase] Default app available (native init)');
  } catch (_) {
    if (Platform.isAndroid) {
      try {
        await Firebase.initializeApp(options: _kAndroidFirebaseOptions);
        firebaseReady = true;
        // ignore: avoid_print
        print('[Firebase] initializeApp succeeded');
      } catch (initErr) {
        final msg = initErr.toString().toLowerCase();
        if (msg.contains('already exists')) {
          try {
            Firebase.app();
            firebaseReady = true;
          } catch (_) {}
        } else {
          // ignore: avoid_print
          print('[Firebase] init failed: $initErr');
        }
      }
    } else {
      // iOS fallback: do NOT call initializeApp with Android options.
      // ignore: avoid_print
      print('[Firebase] iOS native init did not register [DEFAULT] app');
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
