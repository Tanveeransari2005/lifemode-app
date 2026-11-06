package com.tanveer.lifemode

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.AlarmClock
import android.provider.Settings
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat

object Notifs {
    const val CH_SERVICE = "lm_mode"        // ongoing mode card (silent)
    const val CH_ALERT = "lm_alert"         // arriving home, focus done
    const val CH_SUGGEST = "lm_suggest"     // proactive suggestions
    const val ID_SERVICE = 1
    const val ID_ALERT = 2
    const val ID_SUGGEST = 3
    const val ID_NUDGE = 4
    const val ID_BOOT = 5
    const val ID_BLOCK = 6

    fun channels(c: Context) {
        if (Build.VERSION.SDK_INT < 26) return
        val nm = c.getSystemService(NotificationManager::class.java)
        nm.createNotificationChannel(NotificationChannel(CH_SERVICE, "Current mode", NotificationManager.IMPORTANCE_LOW).apply {
            description = "Shows the active Life Mode and its quick actions"; setShowBadge(false)
        })
        nm.createNotificationChannel(NotificationChannel(CH_ALERT, "Mode alerts", NotificationManager.IMPORTANCE_DEFAULT).apply {
            description = "Arrived home, focus timer done"
        })
        nm.createNotificationChannel(NotificationChannel(CH_SUGGEST, "Smart suggestions", NotificationManager.IMPORTANCE_DEFAULT).apply {
            description = "At most one small suggestion every 30 minutes"
        })
    }

    private var reqCode = 100
    private fun flags(mutable: Boolean = false) =
        PendingIntent.FLAG_UPDATE_CURRENT or (if (mutable && Build.VERSION.SDK_INT >= 31) PendingIntent.FLAG_MUTABLE else PendingIntent.FLAG_IMMUTABLE)

    fun openApp(c: Context): PendingIntent {
        val i = c.packageManager.getLaunchIntentForPackage(c.packageName) ?: Intent(c, MainActivity::class.java)
        i.flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP
        return PendingIntent.getActivity(c, 1, i, flags())
    }

    fun activity(c: Context, i: Intent): PendingIntent {
        i.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        return PendingIntent.getActivity(c, reqCode++, i, flags())
    }

    /** Non-UI actions go to the service. */
    fun serviceAction(c: Context, action: String, extra: String = ""): PendingIntent {
        val i = Intent(c, ContextService::class.java).setAction(action).putExtra("extra", extra)
        return if (Build.VERSION.SDK_INT >= 26) PendingIntent.getForegroundService(c, reqCode++, i, flags())
        else PendingIntent.getService(c, reqCode++, i, flags())
    }

    // ---- intents that open other apps (never send anything silently) ----
    fun mapsIntent(c: Context): Intent =
        c.packageManager.getLaunchIntentForPackage("com.google.android.apps.maps")
            ?: Intent(Intent.ACTION_VIEW, Uri.parse("geo:0,0?q="))

    fun familyIntent(c: Context, text: String): Intent {
        val cfg = Store.config(c)
        val phone = cfg.optString("familyPhone", "").filter { it.isDigit() }
        return if (cfg.optString("homeChannel", "whatsapp") == "sms") {
            Intent(Intent.ACTION_SENDTO, Uri.parse("smsto:$phone")).putExtra("sms_body", text)
        } else {
            val url = if (phone.isEmpty()) "https://wa.me/?text=${Uri.encode(text)}" else "https://wa.me/$phone?text=${Uri.encode(text)}"
            Intent(Intent.ACTION_VIEW, Uri.parse(url))
        }
    }

    fun locationText(c: Context): String {
        val lat = Live.lastLat; val lng = Live.lastLng
        val where = if (lat != null && lng != null) " https://maps.google.com/?q=$lat,$lng" else ""
        return Store.s(c, "Meri battery low hai. Main yahan hoon:$where", "My battery is low. I'm here:$where")
    }

    fun batterySaverIntent(): Intent =
        if (Build.VERSION.SDK_INT >= 22) Intent(Settings.ACTION_BATTERY_SAVER_SETTINGS) else Intent(Settings.ACTION_SETTINGS)

    fun setAlarmIntent(): Intent = Intent(AlarmClock.ACTION_SET_ALARM)

    fun canPost(c: Context) = NotificationManagerCompat.from(c).areNotificationsEnabled()

    @Suppress("MissingPermission")
    fun post(c: Context, id: Int, b: NotificationCompat.Builder) {
        if (!canPost(c)) return
        try { NotificationManagerCompat.from(c).notify(id, b.build()) } catch (_: SecurityException) {}
    }

    fun base(c: Context, ch: String, title: String, text: String) = NotificationCompat.Builder(c, ch)
        .setSmallIcon(R.drawable.ic_stat_lifemode)
        .setContentTitle(title).setContentText(text)
        .setStyle(NotificationCompat.BigTextStyle().bigText(text))
        .setContentIntent(openApp(c))
        .setColor(0xFF5B4BDB.toInt())
}
