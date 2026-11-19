package com.appicator.itp_voice

import android.content.Context
import android.os.Handler
import android.os.Looper
import android.util.Log
import com.hiennv.flutter_callkit_incoming.CallkitIncomingBroadcastReceiver
import com.hiennv.flutter_callkit_incoming.Data
import com.hiennv.flutter_callkit_incoming.FlutterCallkitIncomingPlugin
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.FlutterEngineCache
import io.flutter.embedding.engine.dart.DartExecutor
import io.flutter.plugin.common.MethodChannel
import java.util.UUID
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit

/**
 * App-wake, Android half (CONTRACT.md in the workbench .scratch/app-wake).
 *
 * A high-priority FCM data message `type=voice360_call` arrives in
 * [AppWakeMessagingService]. On `ring` this shows the incoming call at once
 * (flutter_callkit_incoming: self-managed Telecom connection + full-screen
 * intent notification), makes sure the app's single Flutter engine is running
 * (starting it with no screen when the app was killed) and hands the push to
 * Dart over the `voice360/app_wake` channel, where CallWakeService registers
 * SIP and takes the INVITE. On `cancel` it takes the call UI down as missed,
 * unless the call was already answered or ended here.
 */
object AppWake {
    const val TAG = "AppWake"
    const val PUSH_TYPE = "voice360_call"
    // Same id audio_service caches its engine under (AudioServicePlugin.
    // getFlutterEngine): with any other id audio_service starts a SECOND engine
    // that runs main() again, so the app would have two Dart isolates.
    private const val ENGINE_ID = "audio_service_engine"
    private const val CHANNEL = "voice360/app_wake"
    private const val PREFS = "voice360_app_wake"
    private const val KEY_ENDED = "ended_call_ids"

    private val main = Handler(Looper.getMainLooper())
    private var appContext: Context? = null
    private var channel: MethodChannel? = null
    private var dartReady = false
    private val queue = mutableListOf<Map<String, Any?>>()

    /** call_id -> "ringing" | "answered", for calls shown in this process. */
    private val active = mutableMapOf<String, String>()

    fun uuidFor(callId: String): String =
        UUID.nameUUIDFromBytes("voice360:$callId".toByteArray()).toString()

    /** The process-wide engine; MainActivity attaches to the same one. Main thread only. */
    fun engine(context: Context): FlutterEngine {
        val app = context.applicationContext
        appContext = app
        FlutterEngineCache.getInstance().get(ENGINE_ID)?.let {
            // audio_service may have created it first; make sure our channel is on it.
            if (boundEngine !== it) bindChannel(it)
            return it
        }
        val engine = FlutterEngine(app)
        bindChannel(engine)
        engine.dartExecutor.executeDartEntrypoint(DartExecutor.DartEntrypoint.createDefault())
        FlutterEngineCache.getInstance().put(ENGINE_ID, engine)
        Log.d(TAG, "Flutter engine started")
        return engine
    }

    private var boundEngine: FlutterEngine? = null

    private fun bindChannel(engine: FlutterEngine) {
        boundEngine = engine
        dartReady = false
        val ch = MethodChannel(engine.dartExecutor.binaryMessenger, CHANNEL)
        channel = ch
        ch.setMethodCallHandler { call, result ->
            try {
                when (call.method) {
                    "ready" -> {
                        dartReady = true
                        val events = ArrayList(queue)
                        queue.clear()
                        result.success(mapOf("events" to events))
                    }
                    "endCall" -> {
                        val callId = call.argument<String>("call_id") ?: ""
                        endUi(appContext, callId,
                            call.argument<String>("reason") ?: "ended")
                        result.success(null)
                    }
                    "connected" -> {
                        val callId = call.argument<String>("call_id") ?: ""
                        active[callId] = "answered"
                        val ctx = appContext
                        if (ctx != null) {
                            ctx.sendBroadcast(CallkitIncomingBroadcastReceiver.getIntentConnected(
                                ctx, callData(callId, "", "").toBundle()))
                        }
                        result.success(null)
                    }
                    "markEnded" -> {
                        val callId = call.argument<String>("call_id") ?: ""
                        appContext?.let { markEnded(it, callId) }
                        result.success(null)
                    }
                    "callOngoing" -> {
                        @Suppress("UNCHECKED_CAST")
                        val args = (call.arguments as? Map<String, Any?>) ?: emptyMap()
                        appContext?.let { CallOngoingService.startOrUpdate(it, args) }
                        result.success(null)
                    }
                    "callEnded" -> {
                        appContext?.let { CallOngoingService.stop(it) }
                        result.success(null)
                    }
                    "getVoipToken" -> result.success(null)
                    "beginBackground", "endBackground" -> result.success(null)
                    else -> result.notImplemented()
                }
            } catch (e: Exception) {
                Log.w(TAG, "channel ${call.method} failed: ${e.message}")
                result.error("app_wake", e.message, null)
            }
        }
    }


    /** Called on an FCM worker thread. Waits (max 4 s) for the main-thread work. */
    fun onPush(context: Context, data: Map<String, String>, receivedAtMs: Long) {
        appContext = context.applicationContext
        val done = CountDownLatch(1)
        main.post {
            try {
                handlePush(context.applicationContext, data, receivedAtMs)
            } catch (e: Exception) {
                Log.e(TAG, "push handling failed", e)
            } finally {
                done.countDown()
            }
        }
        try {
            done.await(4, TimeUnit.SECONDS)
        } catch (_: InterruptedException) {
        }
    }

    private fun handlePush(context: Context, data: Map<String, String>, receivedAtMs: Long) {
        val action = data["action"] ?: ""
        val callId = data["call_id"] ?: ""
        if (callId.isEmpty()) return
        val cold = FlutterEngineCache.getInstance().get(ENGINE_ID) == null
        Log.d(TAG, "push $action $callId (engine ${if (cold) "cold" else "running"})")
        val result: String
        when (action) {
            "ring" -> {
                when {
                    isEnded(context, callId) -> {
                        Log.d(TAG, "ring for ended call $callId ignored")
                        return
                    }
                    active.containsKey(callId) -> {
                        Log.d(TAG, "duplicate ring $callId")
                        return
                    }
                }
                // Engine first: the plugin instance that draws the call UI
                // lives on an engine.
                engine(context)
                active[callId] = "ringing"
                val d = callData(callId, data["caller_id_number"] ?: "", data["caller_id_name"] ?: "")
                val plugin = FlutterCallkitIncomingPlugin.getInstance()
                if (plugin != null) {
                    plugin.showIncomingNotification(d)
                } else {
                    context.sendBroadcast(
                        CallkitIncomingBroadcastReceiver.getIntentIncoming(context, d.toBundle()))
                }
                result = "shown"
            }
            "cancel" -> {
                val state = active[callId]
                result = when {
                    state == null -> "ignored (not active here)" // F4, or never shown
                    state == "answered" -> "ignored (answered)"
                    else -> {
                        endUi(context, callId, "missed")
                        "ended"
                    }
                }
                Log.d(TAG, "cancel $callId: $result")
                if (state == null || state == "answered") {
                    // Nothing for Dart to do unless the engine is up anyway.
                    if (FlutterEngineCache.getInstance().get(ENGINE_ID) == null) return
                }
            }
            else -> return
        }
        val event = HashMap<String, Any?>(data)
        event["event"] = "push"
        event["uuid"] = uuidFor(callId)
        event["received_at_ms"] = receivedAtMs.toString()
        event["native_result"] = result
        event["cold_start"] = if (cold) "1" else "0"
        sendToDart(event)
    }

    /** Ongoing-call notification tap or button -> Dart ActiveCallService. */
    fun callAction(context: Context, action: String) {
        appContext = context.applicationContext
        main.post {
            if (FlutterEngineCache.getInstance().get(ENGINE_ID) == null) {
                // No Dart left to act on the call: drop the stale notification.
                if (action != "open") CallOngoingService.stop(context.applicationContext)
                return@post
            }
            sendToDart(mapOf("event" to "callAction", "action" to action))
        }
    }

    private fun sendToDart(event: Map<String, Any?>) {
        val ch = channel
        if (ch != null && dartReady) {
            ch.invokeMethod("onEvent", event)
        } else {
            queue.add(event)
            if (queue.size > 20) queue.removeAt(0)
        }
    }

    /** Take the call UI down. reason: missed | ended | failed | declined. */
    private fun endUi(context: Context?, callId: String, reason: String) {
        if (context == null || callId.isEmpty()) return
        val state = active.remove(callId)
        markEnded(context, callId)
        if (state == null) return
        val bundle = callData(callId, "", "").toBundle()
        val intent = if (reason == "missed" && state == "ringing") {
            CallkitIncomingBroadcastReceiver.getIntentTimeout(context, bundle)
        } else {
            CallkitIncomingBroadcastReceiver.getIntentEnded(context, bundle)
        }
        context.sendBroadcast(intent)
        Log.d(TAG, "call UI ended for $callId ($reason)")
    }

    private fun callData(callId: String, number: String, name: String): Data {
        val android = hashMapOf<String, Any?>(
            "isCustomNotification" to false,
            "isShowFullLockedScreen" to true,
            "isFullScreen" to false,
            "isImportant" to true,
            "backgroundColor" to "#0b1f3a",
            "actionColor" to "#2e7d32",
            "textColor" to "#ffffff",
            "incomingCallNotificationChannelName" to "Incoming calls",
            "missedCallNotificationChannelName" to "Missed calls",
            "textAccept" to "Answer",
            "textDecline" to "Decline",
        )
        val args = hashMapOf<String, Any?>(
            "id" to uuidFor(callId),
            "nameCaller" to name.ifEmpty { number.ifEmpty { "Unknown caller" } },
            "appName" to "VOICE360",
            "handle" to number,
            "type" to 0,
            // The dialplan's cancel push (or SIP CANCEL) ends the ring; this is
            // only a backstop.
            "duration" to 90000L,
            "extra" to hashMapOf<String, Any?>("call_id" to callId),
            "missedCallNotification" to hashMapOf<String, Any?>(
                "showNotification" to true,
                "isShowCallback" to false,
                "subtitle" to "Missed call",
            ),
            // The app posts its own ongoing-call notification for every call
            // (CallOngoingService: tap returns to the call, Mute/Speaker/Hang
            // up). The plugin's has no tap action and only Hang up.
            "callingNotification" to hashMapOf<String, Any?>(
                "showNotification" to false,
                "isShowCallback" to true,
                "subtitle" to "VOICE360 call",
                "callbackText" to "Hang up",
            ),
            "android" to android,
        )
        return Data(args)
    }

    private fun isEnded(context: Context, callId: String): Boolean =
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .getString(KEY_ENDED, "")!!.split('\n').contains(callId)

    private fun markEnded(context: Context, callId: String) {
        if (callId.isEmpty()) return
        active.remove(callId)
        val p = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        val list = p.getString(KEY_ENDED, "")!!.split('\n').filter { it.isNotEmpty() && it != callId }
            .takeLast(29) + callId
        p.edit().putString(KEY_ENDED, list.joinToString("\n")).apply()
    }
}
