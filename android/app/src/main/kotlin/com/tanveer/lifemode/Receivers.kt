package com.tanveer.lifemode

import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build
import com.google.android.gms.location.ActivityTransition
import com.google.android.gms.location.ActivityTransitionResult
import com.google.android.gms.location.DetectedActivity
import com.google.android.gms.location.Geofence
import com.google.android.gms.location.GeofencingEvent

object Receivers {
    private fun mutableFlags() = PendingIntent.FLAG_UPDATE_CURRENT or (if (Build.VERSION.SDK_INT >= 31) PendingIntent.FLAG_MUTABLE else 0)
    fun activityPi(c: Context): PendingIntent =
        PendingIntent.getBroadcast(c, 11, Intent(c, ActivityRx::class.java).setAction("com.tanveer.lifemode.ACTIVITY"), mutableFlags())
    fun geofencePi(c: Context): PendingIntent =
        PendingIntent.getBroadcast(c, 12, Intent(c, GeofenceRx::class.java).setAction("com.tanveer.lifemode.GEOFENCE"), mutableFlags())
}

/** Activity Recognition Transition API -> service. */
class ActivityRx : BroadcastReceiver() {
    override fun onReceive(c: Context, i: Intent) {
        if (!ActivityTransitionResult.hasResult(i)) return
        val events = ActivityTransitionResult.extractResult(i)?.transitionEvents ?: return
        val ev = events.lastOrNull { it.transitionType == ActivityTransition.ACTIVITY_TRANSITION_ENTER }
        if (ev == null) { ContextService.start(c, ContextService.ACTION_ACTIVITY, ""); return }
        val name = when (ev.activityType) {
            DetectedActivity.IN_VEHICLE -> "IN_VEHICLE"
            DetectedActivity.ON_BICYCLE -> "ON_BICYCLE"
            DetectedActivity.WALKING -> "WALKING"
            DetectedActivity.RUNNING -> "RUNNING"
            DetectedActivity.STILL -> "STILL"
            else -> "UNKNOWN"
        }
        ContextService.start(c, ContextService.ACTION_ACTIVITY, name)
    }
}

class GeofenceRx : BroadcastReceiver() {
    override fun onReceive(c: Context, i: Intent) {
        val ev = GeofencingEvent.fromIntent(i) ?: return
        if (ev.hasError()) return
        val t = when (ev.geofenceTransition) {
            Geofence.GEOFENCE_TRANSITION_ENTER, Geofence.GEOFENCE_TRANSITION_DWELL -> "enter"
            Geofence.GEOFENCE_TRANSITION_EXIT -> "exit"
            else -> return
        }
        ContextService.start(c, ContextService.ACTION_GEOFENCE, t)
    }
}

/** Restart after reboot / app update (if the user left LifeMode on). */
class BootRx : BroadcastReceiver() {
    override fun onReceive(c: Context, i: Intent) {
        val cfg = Store.config(c)
        IconSwitcher.schedule(c)
        if (!cfg.optBoolean("onboarded", false) || !cfg.optBoolean("engineOn", true)) return
        ContextService.start(c)
    }
}

/** While-idle alarm -> tick (service already running in this process). */
class TickRx : BroadcastReceiver() {
    override fun onReceive(c: Context, i: Intent) {
        ContextService.instance?.let { svc -> svc.h.post { svc.handle(ContextService.ACTION_TICK, "") } }
    }
}
