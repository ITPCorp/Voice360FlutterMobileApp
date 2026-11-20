package com.appicator.itp_voice

import android.app.NotificationManager
import android.content.ActivityNotFoundException
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.Settings

internal object FullScreenCalls {
    fun allowed(context: Context): Boolean = Build.VERSION.SDK_INT < 34 ||
        context.getSystemService(NotificationManager::class.java).canUseFullScreenIntent()

    fun openSettings(context: Context): Boolean {
        val pkg = Uri.fromParts("package", context.packageName, null)
        val intents = buildList {
            if (Build.VERSION.SDK_INT >= 34) add(Intent(Settings.ACTION_MANAGE_APP_USE_FULL_SCREEN_INTENT, pkg))
            if (Build.VERSION.SDK_INT >= 26) add(Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS)
                .putExtra(Settings.EXTRA_APP_PACKAGE, context.packageName))
            add(Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, pkg))
        }
        for (intent in intents) {
            try {
                context.startActivity(intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
                return true
            } catch (_: ActivityNotFoundException) {
                continue
            } catch (_: SecurityException) {
                continue
            }
        }
        return false
    }
}
