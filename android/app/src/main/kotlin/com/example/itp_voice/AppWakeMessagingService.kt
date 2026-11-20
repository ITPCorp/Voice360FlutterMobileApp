package com.appicator.itp_voice

import android.content.Intent
import com.google.firebase.messaging.RemoteMessage
import io.flutter.plugins.firebase.messaging.FlutterFirebaseMessagingService

/**
 * Replaces firebase_messaging's FlutterFirebaseMessagingService (removed in
 * the manifest). voice360_call data messages (app-wake, CONTRACT.md) are
 * handled natively so the call UI shows before any Dart runs; everything else
 * (token refresh, SMS pushes) goes through firebase_messaging as before.
 */
class AppWakeMessagingService : FlutterFirebaseMessagingService() {
    override fun handleIntent(intent: Intent) {
        NotificationInbox.tagFirebaseNotification(intent)
        super.handleIntent(intent)
    }

    override fun onMessageReceived(remoteMessage: RemoteMessage) {
        val data = remoteMessage.data
        if (data["type"] == AppWake.PUSH_TYPE) {
            AppWake.onPush(applicationContext, data, System.currentTimeMillis())
            return
        }
        super.onMessageReceived(remoteMessage)
    }
}
