package com.appicator.itp_voice

import android.app.NotificationManager
import android.content.Context
import android.content.Intent
import android.os.Build
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import org.json.JSONObject

internal object NotificationInbox {
    private const val prefix = "voice360.inbox:"
    private const val missedChannel = "callkit_missed_channel_id"
    private val routeFields = listOf(
        "type", "item_type", "event_type", "notification_type", "metadata",
        "message_thread_id", "message_thread_pk", "thread_id", "conversation_id",
        "voicemail_msg_id", "msg_id", "voicemail_message_id", "voice_message_id",
        "voicemail_message_pk", "voicemail_id"
    )

    // FCM normally assigns a time-based tag and drops the data payload from
    // the shade entry. Keep the routing data on that entry across process death.
    fun tagFirebaseNotification(intent: Intent) {
        val extras = intent.extras ?: return
        if (extras.getString("type") == AppWake.PUSH_TYPE) return
        if (extras.getString("gcm.n.e") != "1" && extras.getString("gcm.notification.e") != "1") return
        val payload = JSONObject()
        for (field in routeFields) extras.getString(field)?.let { payload.put(field, it) }
        if (payload.length() == 0) return
        intent.putExtra("gcm.n.tag", prefix + payload.toString())
    }

    fun attach(context: Context, messenger: BinaryMessenger) {
        val notifications = context.getSystemService(NotificationManager::class.java)
        MethodChannel(messenger, "voice360/notification_inbox").setMethodCallHandler { call, result ->
            when (call.method) {
                "visibleThread" -> {
                    SmsNotification.visibleThread = call.arguments as? String
                    result.success(null)
                }
                "active" -> result.success(notifications.activeNotifications.mapNotNull { entry ->
                    val note = entry.notification
                    val missed = note.extras.getBoolean("voice360.missed") ||
                        (Build.VERSION.SDK_INT >= 26 && note.channelId == missedChannel)
                    val tag = entry.tag
                    val payload = when {
                        missed -> """{"type":"missed_call"}"""
                        tag?.startsWith(prefix) == true -> tag.removePrefix(prefix)
                        else -> return@mapNotNull null
                    }
                    mapOf("key" to listOf(tag, entry.id), "payload" to payload)
                })
                "remove" -> {
                    val keys = call.arguments as? List<*> ?: emptyList<Any>()
                    for (key in keys.filterIsInstance<List<*>>()) {
                        val id = key.getOrNull(1) as? Int ?: continue
                        notifications.cancel(key.firstOrNull() as? String, id)
                    }
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }
}
