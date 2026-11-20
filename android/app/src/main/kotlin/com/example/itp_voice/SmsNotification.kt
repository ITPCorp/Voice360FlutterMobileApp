package com.appicator.itp_voice

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build
import androidx.core.app.NotificationCompat
import androidx.core.app.Person
import com.google.firebase.messaging.RemoteMessage
import org.json.JSONObject

/** One shade entry per SMS thread. Android retains its message history until dismissed. */
internal object SmsNotification {
    const val OPEN = "com.appicator.itp_voice.OPEN_SMS_THREAD"
    private const val channel = "itpvoice"
    private const val marker = "voice360.render_sms"
    @Volatile var resumed = false
    @Volatile var visibleThread: String? = null

    // This CRM sender includes the peer in the legacy alert body, while the
    // actual SMS text is in data.message. Metadata can be a Python dictionary.
    fun prepare(intent: Intent): Boolean {
        val extras = intent.extras ?: return false
        if (extras.getString("service_name") != "itp_voice" ||
            extras.getString("type") == AppWake.PUSH_TYPE) return false
        if (extras.getString("gcm.n.e") != "1" && extras.getString("gcm.notification.e") != "1") return false
        val metadata = runCatching { JSONObject(extras.getString("metadata") ?: "{}") }.getOrNull()
        val thread = listOf("message_thread_id", "message_thread_pk", "thread_id", "conversation_id")
            .firstNotNullOfOrNull { key -> (extras.getString(key) ?: metadata?.optString(key))?.takeIf { it.isNotBlank() } }
        if (thread.isNullOrBlank() || thread == "null" || thread == "None") return false
        val legacy = extras.getString("gcm.n.body") ?: extras.getString("gcm.notification.body").orEmpty()
        val peer = extras.getString("from_number") ?: metadata?.optString("from_number")?.takeIf { it.isNotBlank() }
            ?: Regex("""(?i)^New Message from ([+()\d .-]+)$""").matchEntire(legacy)?.groupValues?.get(1)
        intent.putExtra(marker, thread)
        intent.putExtra("voice360.sender", peer)
        intent.putExtra("voice360.owner", extras.getString("to_phone_number") ?: metadata?.optString("to_phone_number"))
        // Firebase still handles transport and message-ID deduplication. Its
        // data dispatch below replaces the generic notification renderer.
        intent.removeExtra("gcm.n.e")
        intent.removeExtra("gcm.notification.e")
        return true
    }

    fun show(context: Context, remote: RemoteMessage): Boolean {
        val data = remote.data
        val thread = data[marker] ?: return false
        if (resumed && visibleThread == thread) return true
        val manager = context.getSystemService(NotificationManager::class.java)
        if (Build.VERSION.SDK_INT >= 26) {
            manager.createNotificationChannel(NotificationChannel(channel, "VOICE360", NotificationManager.IMPORTANCE_HIGH))
        }
        val tag = "voice360.inbox:" + JSONObject().put("message_thread_id", thread)
        val previous = manager.activeNotifications.firstOrNull { it.tag == tag && it.id == 0 }
        val peer = data["voice360.sender"].orEmpty()
        val digits = peer.filter(Char::isDigit).let { if (it.length == 11 && it.startsWith('1')) it.drop(1) else it }
        val names = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
            .getString("flutter.sms_notification_names", null)
        val name = names?.let { runCatching { JSONObject(it).optString(digits) }.getOrNull() }.orEmpty()
        val title = name.ifBlank {
            if (digits.length == 10) "(${digits.take(3)}) ${digits.substring(3, 6)}-${digits.takeLast(4)}"
            else peer.ifBlank { "Messages" }
        }
        val sender = Person.Builder().setName(title).setKey(peer.ifBlank { thread }).build()
        val style = previous?.let { NotificationCompat.MessagingStyle.extractMessagingStyleFromNotification(it.notification) }
            ?: NotificationCompat.MessagingStyle(Person.Builder().setName("You").build())
        val body = data["message"].orEmpty().ifBlank {
            if (data["media_type"]?.startsWith("image/") == false) "Attachment" else "Photo"
        }
        style.addMessage(body, remote.sentTime.takeIf { it > 0 } ?: System.currentTimeMillis(), sender)
        val open = Intent(context, MainActivity::class.java).apply {
            action = OPEN
            addCategory("voice360.thread.$thread")
            flags = Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP
            putExtra("message_thread_id", thread)
            putExtra("to_phone_number", data["voice360.owner"])
            putExtra("from_number", peer)
        }
        val tap = PendingIntent.getActivity(context, 0, open, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        val note = NotificationCompat.Builder(context, channel)
            .setSmallIcon(R.drawable.ic_stat_voice360).setCategory(NotificationCompat.CATEGORY_MESSAGE)
            .setStyle(style).setAutoCancel(true).setContentIntent(tap)
            .setVisibility(NotificationCompat.VISIBILITY_PRIVATE).setPriority(NotificationCompat.PRIORITY_HIGH)
            .build()
        manager.notify(tag, 0, note)
        return true
    }
}
