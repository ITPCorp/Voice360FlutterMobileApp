package com.appicator.itp_voice

import android.content.Context
import android.media.AudioManager
import android.os.Build
import android.os.PowerManager
import android.util.Log

/** The display follows the proximity sensor only during connected earpiece audio. */
internal object CallProximity {
    private var eligible = false
    private var uuid: String? = null
    private var lock: PowerManager.WakeLock? = null
    private var listener: AudioManager.OnCommunicationDeviceChangedListener? = null

    fun setEligible(context: Context, enabled: Boolean, nativeUuid: String?) {
        eligible = enabled
        uuid = nativeUuid
        if (Build.VERSION.SDK_INT >= 31) {
            val audio = context.getSystemService(AudioManager::class.java)
            if (enabled && listener == null) {
                val callback = AudioManager.OnCommunicationDeviceChangedListener {
                    if (eligible) route(context, AudioRoutes.state(context, uuid))
                }
                audio.addOnCommunicationDeviceChangedListener(context.mainExecutor, callback)
                listener = callback
            } else if (!enabled) {
                listener?.let { audio.removeOnCommunicationDeviceChangedListener(it) }
                listener = null
            }
        }
        if (enabled) route(context, AudioRoutes.state(context, uuid)) else release()
    }

    fun route(context: Context, route: Map<String, Any?>) {
        if (!eligible || route["earpiece_active"] != true) {
            release()
            return
        }
        val power = context.getSystemService(PowerManager::class.java)
        if (!power.isWakeLockLevelSupported(PowerManager.PROXIMITY_SCREEN_OFF_WAKE_LOCK)) return
        val screen = lock ?: power.newWakeLock(PowerManager.PROXIMITY_SCREEN_OFF_WAKE_LOCK,
            "Voice360:earpiece").apply { setReferenceCounted(false) }.also { lock = it }
        if (!screen.isHeld) {
            screen.acquire()
            Log.d("CallProximity", "acquired on earpiece")
        }
    }

    fun release() {
        lock?.takeIf { it.isHeld }?.let {
            it.release()
            Log.d("CallProximity", "released")
        }
    }
}
