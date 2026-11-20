package com.appicator.itp_voice

import android.Manifest
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import android.util.Log
import androidx.core.app.NotificationCompat
import androidx.core.content.ContextCompat

/**
 * Ongoing-call notification + foreground service for every active call
 * (outbound, in-app incoming, woken by a push). Dart's ActiveCallService
 * starts/updates it over voice360/app_wake ("callOngoing") and stops it
 * ("callEnded").
 *
 * - Tapping it opens the app on the in-call screen (MainActivity ACTION_OPEN_CALL).
 * - Actions: Mute/Unmute, Speaker, Hang up (CallActionReceiver -> Dart).
 * - Foreground service type phoneCall (+ microphone when granted) keeps the
 *   mic working while the app is in the background, which the app never had
 *   for outbound or in-app calls.
 */
class CallOngoingService : Service() {

    companion object {
        private const val TAG = "CallOngoing"
        // IMPORTANCE_DEFAULT (silent): a LOW channel puts the notification in the
        // collapsed "Silent" section where its buttons are hidden.
        private const val CHANNEL_ID = "voice360_call_active"
        const val NOTIFICATION_ID = 0x0360CA11

        fun startOrUpdate(context: Context, args: Map<String, Any?>) {
            val i = Intent(context, CallOngoingService::class.java).apply {
                putExtra("name", args["name"] as? String ?: "")
                putExtra("number", args["number"] as? String ?: "")
                putExtra("connected_at_ms", (args["connected_at_ms"] as? Number)?.toLong() ?: 0L)
                putExtra("muted", args["muted"] as? Boolean ?: false)
                putExtra("speaker", args["speaker"] as? Boolean ?: false)
                putExtra("status", args["status"] as? String ?: "On call")
            }
            try {
                ContextCompat.startForegroundService(context, i)
            } catch (e: Exception) {
                // Not allowed to start a foreground service right now (app in the
                // background on Android 12+): still post the notification.
                Log.w(TAG, "startForegroundService refused: ${e.message}")
                (context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager)
                    .notify(NOTIFICATION_ID, build(context, i, callStyle = false))
            }
        }

        fun stop(context: Context) {
            context.stopService(Intent(context, CallOngoingService::class.java))
            (context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager)
                .cancel(NOTIFICATION_ID)
        }

        private fun ensureChannel(context: Context) {
            if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
            val nm = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            if (nm.getNotificationChannel(CHANNEL_ID) == null) {
                nm.createNotificationChannel(
                    NotificationChannel(CHANNEL_ID, "Calls in progress", NotificationManager.IMPORTANCE_DEFAULT)
                        .apply {
                            setSound(null, null)
                            enableVibration(false)
                            setShowBadge(false)
                        }
                )
            }
        }

        private fun flags(): Int =
            PendingIntent.FLAG_UPDATE_CURRENT or
                (if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) PendingIntent.FLAG_IMMUTABLE else 0)

        /**
         * callStyle = Android's call notification (top of the shade, caller,
         * timer, Hang up button). Only allowed for a foreground service, so the
         * fallback path (no foreground service) posts the plain style.
         */
        fun build(context: Context, i: Intent, callStyle: Boolean = true): Notification {
            ensureChannel(context)
            val name = i.getStringExtra("name").orEmpty()
            val number = i.getStringExtra("number").orEmpty()
            val connectedAt = i.getLongExtra("connected_at_ms", 0L)
            val muted = i.getBooleanExtra("muted", false)
            val speaker = i.getBooleanExtra("speaker", false)
            val status = i.getStringExtra("status") ?: "On call"

            val open = PendingIntent.getActivity(
                context, 1,
                Intent(context, MainActivity::class.java).apply {
                    action = MainActivity.ACTION_OPEN_CALL
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP)
                },
                flags()
            )
            fun action(a: String, req: Int) = PendingIntent.getBroadcast(
                context, req,
                Intent(context, CallActionReceiver::class.java).setAction(a),
                flags()
            )

            val hangup = action(CallActionReceiver.HANGUP, 4)
            val b = NotificationCompat.Builder(context, CHANNEL_ID)
                .setSmallIcon(R.drawable.ic_stat_voice360)
                .setLargeIcon(android.graphics.BitmapFactory.decodeResource(context.resources, R.drawable.notification_voice360))
                .setContentTitle(if (name.isNotEmpty()) name else number)
                .setContentText(
                    "$status${if (muted) " · muted" else ""}${if (speaker) " · speaker" else ""} · tap to return"
                )
                .setCategory(NotificationCompat.CATEGORY_CALL)
                .setOngoing(true)
                .setOnlyAlertOnce(true)
                .setSilent(true)
                .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
                .setContentIntent(open)
                .setPriority(NotificationCompat.PRIORITY_HIGH)
                .addAction(0, if (muted) "Unmute" else "Mute", action(CallActionReceiver.MUTE, 2))
                .addAction(0, if (speaker) "Speaker off" else "Speaker", action(CallActionReceiver.SPEAKER, 3))
            if (callStyle) {
                val person = androidx.core.app.Person.Builder()
                    .setName(if (name.isNotEmpty()) name else number.ifEmpty { "Call" })
                    .setIcon(androidx.core.graphics.drawable.IconCompat.createWithResource(context, R.drawable.notification_voice360))
                    .setImportant(true)
                    .build()
                b.setStyle(NotificationCompat.CallStyle.forOngoingCall(person, hangup))
            } else {
                b.addAction(0, "Hang up", hangup)
            }
            if (connectedAt > 0) {
                b.setWhen(connectedAt).setShowWhen(true).setUsesChronometer(true)
            } else {
                b.setShowWhen(false)
            }
            return b.build()
        }
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val n = try {
            build(this, intent ?: Intent())
        } catch (e: Exception) {
            Log.w(TAG, "CallStyle failed, plain notification: ${e.message}")
            build(this, intent ?: Intent(), callStyle = false)
        }
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                var type = ServiceInfo.FOREGROUND_SERVICE_TYPE_PHONE_CALL
                if (ContextCompat.checkSelfPermission(this, Manifest.permission.RECORD_AUDIO)
                    == PackageManager.PERMISSION_GRANTED && Build.VERSION.SDK_INT >= Build.VERSION_CODES.R
                ) {
                    type = type or ServiceInfo.FOREGROUND_SERVICE_TYPE_MICROPHONE
                }
                try {
                    startForeground(NOTIFICATION_ID, n, type)
                } catch (e: Exception) {
                    // Microphone type refused from the background: phoneCall only.
                    Log.w(TAG, "startForeground($type) refused: ${e.message}")
                    startForeground(NOTIFICATION_ID, n, ServiceInfo.FOREGROUND_SERVICE_TYPE_PHONE_CALL)
                }
            } else {
                startForeground(NOTIFICATION_ID, n)
            }
        } catch (e: Exception) {
            Log.w(TAG, "foreground refused, plain notification: ${e.message}")
            (getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager).notify(NOTIFICATION_ID, n)
            stopSelf()
        }
        return START_NOT_STICKY
    }

    // Swiping the app away: the call engine lives on in the cached engine; keep going.
    override fun onTaskRemoved(rootIntent: Intent?) {}
}

/** Mute / Speaker / Hang up buttons on the ongoing-call notification. */
class CallActionReceiver : BroadcastReceiver() {
    companion object {
        const val MUTE = "com.appicator.itp_voice.CALL_MUTE"
        const val SPEAKER = "com.appicator.itp_voice.CALL_SPEAKER"
        const val HANGUP = "com.appicator.itp_voice.CALL_HANGUP"
    }

    override fun onReceive(context: Context, intent: Intent) {
        val a = when (intent.action) {
            MUTE -> "mute"
            SPEAKER -> "speaker"
            HANGUP -> "hangup"
            else -> return
        }
        AppWake.callAction(context, a)
    }
}
