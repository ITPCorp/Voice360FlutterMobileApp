package com.appicator.itp_voice

import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.Bundle
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

/**
 * Uses the one process-wide Flutter engine ([AppWake.engine]) so a call that
 * woke the app (FCM -> AppWakeMessagingService, engine started with no screen,
 * SIP already registering) is the same Dart isolate this screen shows.
 */
class MainActivity : FlutterActivity() {

    override fun provideFlutterEngine(context: Context): FlutterEngine =
        AppWake.engine(context.applicationContext)

    // The engine outlives the screen: it may be carrying a call.
    override fun shouldDestroyEngineWithHost(): Boolean = false

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        showOverLockIfCall(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        showOverLockIfCall(intent)
    }

    /** Opened by Answer on the call notification: show over the lock screen. */
    private fun showOverLockIfCall(intent: Intent?) {
        val action = intent?.action ?: return
        if (!action.endsWith("ACTION_CALL_ACCEPT")) return
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
            setShowWhenLocked(true)
            setTurnScreenOn(true)
        } else {
            @Suppress("DEPRECATION")
            window.addFlags(
                WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED or
                    WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON
            )
        }
    }
}
