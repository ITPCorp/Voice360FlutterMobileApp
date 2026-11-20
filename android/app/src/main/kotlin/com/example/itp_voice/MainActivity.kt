package com.appicator.itp_voice

import android.content.Context
import android.content.Intent
import android.os.Build
import io.flutter.plugin.common.MethodChannel
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

    companion object {
        /** Ongoing-call notification tap: open the app on the in-call screen. */
        const val ACTION_OPEN_CALL = "com.appicator.itp_voice.OPEN_CALL"
    }

    override fun provideFlutterEngine(context: Context): FlutterEngine =
        AppWake.engine(context.applicationContext)

    // The engine outlives the screen: it may be carrying a call.
    override fun shouldDestroyEngineWithHost(): Boolean = false

    private var tapChannel: MethodChannel? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        tapChannel = MethodChannel(AppWake.engine(applicationContext).dartExecutor.binaryMessenger, "voice360/notification_taps").also { channel ->
            channel.setMethodCallHandler { call, result ->
                if (call.method == "take") result.success(consumeMissedTap()) else result.notImplemented()
            }
        }
        showOverLockIfCall(intent)
        openCallIfAsked(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        showOverLockIfCall(intent)
        openCallIfAsked(intent)
    }

    private fun openCallIfAsked(intent: Intent?) {
        if (intent?.action == "com.appicator.itp_voice.OPEN_RECENT") tapChannel?.invokeMethod("available", null)
        if (intent?.action == ACTION_OPEN_CALL) AppWake.callAction(this, "open")
    }

    private fun consumeMissedTap(): Map<String, Any?>? {
        val tap = intent ?: return null
        if (tap.action != "com.appicator.itp_voice.OPEN_RECENT") return null
        tap.action = null
        val data = tap.getBundleExtra("EXTRA_CALLKIT_CALL_DATA")
        return mapOf("type" to "missed_call", "caller_name" to data?.getString("EXTRA_CALLKIT_NAME_CALLER"),
            "from_number" to data?.getString("EXTRA_CALLKIT_HANDLE"), "posted_at" to tap.getLongExtra("posted_at", System.currentTimeMillis()))
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
