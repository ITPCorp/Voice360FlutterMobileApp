package com.appicator.itp_voice

import android.content.Context
import android.media.AudioDeviceInfo
import android.media.AudioManager
import android.os.Build
import android.telecom.CallAudioState
import android.util.Log
import com.hiennv.flutter_callkit_incoming.CallkitConnection

/**
 * Call audio route (speaker / earpiece / bluetooth / wired) for the in-call
 * screen's Speaker button.
 *
 * A woken call runs under flutter_callkit_incoming's self-managed Telecom
 * Connection. For those, Telecom owns the route: AudioManager / WebRTC
 * speakerphone changes are reverted, so the route has to go through
 * Connection.setAudioRoute (requestBluetoothAudio for a specific headset).
 * Calls without a Telecom connection (outbound, in-app incoming) are switched
 * by flutter_webrtc on the Dart side; this only reads their route from
 * AudioManager so the button shows what is really playing.
 */
object AudioRoutes {
    private const val TAG = "AudioRoutes"

    private fun connection(uuid: String?): CallkitConnection? {
        if (uuid.isNullOrEmpty() || Build.VERSION.SDK_INT < Build.VERSION_CODES.M) return null
        return CallkitConnection.find(uuid)
    }

    /** {route, available[], via, bluetooth_name} */
    fun state(context: Context, uuid: String?): Map<String, Any?> {
        val conn = connection(uuid)
        @Suppress("DEPRECATION")
        val cs: CallAudioState? = try { conn?.callAudioState } catch (_: Exception) { null }
        if (conn != null && cs != null) {
            val available = mutableListOf<String>()
            if (cs.supportedRouteMask and CallAudioState.ROUTE_EARPIECE != 0) available.add("earpiece")
            if (cs.supportedRouteMask and CallAudioState.ROUTE_WIRED_HEADSET != 0) available.add("wired")
            if (cs.supportedRouteMask and CallAudioState.ROUTE_SPEAKER != 0) available.add("speaker")
            if (cs.supportedRouteMask and CallAudioState.ROUTE_BLUETOOTH != 0) available.add("bluetooth")
            var bt: String? = null
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                try { bt = cs.activeBluetoothDevice?.name } catch (_: SecurityException) {}
            }
            return mapOf(
                "route" to telecomName(cs.route),
                "available" to available,
                "via" to "telecom",
                "bluetooth_name" to bt,
            )
        }
        return audioManagerState(context)
    }

    private fun telecomName(route: Int) = when (route) {
        CallAudioState.ROUTE_SPEAKER -> "speaker"
        CallAudioState.ROUTE_BLUETOOTH -> "bluetooth"
        CallAudioState.ROUTE_WIRED_HEADSET -> "wired"
        else -> "earpiece"
    }

    private fun deviceName(type: Int): String? = when (type) {
        AudioDeviceInfo.TYPE_BUILTIN_SPEAKER -> "speaker"
        AudioDeviceInfo.TYPE_BUILTIN_EARPIECE -> "earpiece"
        AudioDeviceInfo.TYPE_BLUETOOTH_SCO -> "bluetooth"
        AudioDeviceInfo.TYPE_WIRED_HEADSET, AudioDeviceInfo.TYPE_WIRED_HEADPHONES,
        AudioDeviceInfo.TYPE_USB_HEADSET -> "wired"
        else -> if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S &&
            type == AudioDeviceInfo.TYPE_BLE_HEADSET) "bluetooth" else null
    }

    private fun audioManagerState(context: Context): Map<String, Any?> {
        val am = context.getSystemService(Context.AUDIO_SERVICE) as AudioManager
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            val available = am.availableCommunicationDevices.mapNotNull { deviceName(it.type) }.distinct()
            val cur = am.communicationDevice
            val bt = am.availableCommunicationDevices.firstOrNull { deviceName(it.type) == "bluetooth" }
            return mapOf(
                "route" to (cur?.let { deviceName(it.type) } ?: "earpiece"),
                "available" to available,
                "via" to "audiomanager",
                "bluetooth_name" to bt?.productName?.toString(),
            )
        }
        @Suppress("DEPRECATION")
        val route = when {
            am.isSpeakerphoneOn -> "speaker"
            am.isBluetoothScoOn -> "bluetooth"
            am.isWiredHeadsetOn -> "wired"
            else -> "earpiece"
        }
        val available = mutableListOf("earpiece", "speaker")
        @Suppress("DEPRECATION")
        if (am.isWiredHeadsetOn) available.add("wired")
        val outs = am.getDevices(AudioManager.GET_DEVICES_OUTPUTS)
        if (outs.any { it.type == AudioDeviceInfo.TYPE_BLUETOOTH_SCO }) available.add("bluetooth")
        return mapOf("route" to route, "available" to available, "via" to "audiomanager", "bluetooth_name" to null)
    }

    /** Telecom calls only. Returns false when there is no Telecom connection (Dart then uses WebRTC). */
    fun setTelecomRoute(uuid: String?, route: String): Boolean {
        val conn = connection(uuid) ?: return false
        try {
            if (route == "bluetooth" && Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                @Suppress("DEPRECATION")
                val dev = conn.callAudioState?.supportedBluetoothDevices?.firstOrNull()
                if (dev != null) {
                    conn.requestBluetoothAudio(dev)
                    return true
                }
            }
            val mask = when (route) {
                "speaker" -> CallAudioState.ROUTE_SPEAKER
                "bluetooth" -> CallAudioState.ROUTE_BLUETOOTH
                else -> CallAudioState.ROUTE_WIRED_OR_EARPIECE
            }
            // Deprecated in API 34 in favour of requestCallEndpointChange, which
            // needs CallEndpoint objects only the Connection's callbacks hand out
            // (the plugin's Connection does not keep them). setAudioRoute is still
            // honoured by Telecom on 34/35.
            @Suppress("DEPRECATION")
            conn.setAudioRoute(mask)
            Log.d(TAG, "telecom route -> $route")
            return true
        } catch (e: Exception) {
            Log.w(TAG, "telecom route $route failed: ${e.message}")
            return true
        }
    }
}
