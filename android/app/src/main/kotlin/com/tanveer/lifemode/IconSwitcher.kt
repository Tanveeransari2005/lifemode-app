package com.tanveer.lifemode

import android.content.ComponentName
import android.content.Context
import android.content.pm.PackageManager
import androidx.work.ExistingWorkPolicy
import androidx.work.OneTimeWorkRequestBuilder
import androidx.work.WorkManager
import androidx.work.Worker
import androidx.work.WorkerParameters
import java.util.Calendar
import java.util.concurrent.TimeUnit

/** Time-of-day launcher icon via <activity-alias>. Mirrors lib/core/icon_schedule.dart. */
object IconSwitcher {
    val aliases = listOf("morning" to "IconMorning", "afternoon" to "IconAfternoon", "evening" to "IconEvening", "night" to "IconNight")
    const val DEFAULT = "afternoon"
    @Volatile var appVisible = false

    fun variantAt(min: Int): String = when {
        min >= 20 * 60 || min < 6 * 60 -> "night"
        min >= 17 * 60 -> "evening"
        min >= 12 * 60 -> "afternoon"
        else -> "morning"
    }

    fun nextSwitchMs(): Long {
        val now = Calendar.getInstance()
        val m = now.get(Calendar.HOUR_OF_DAY) * 60 + now.get(Calendar.MINUTE)
        val next = listOf(6 * 60, 12 * 60, 17 * 60, 20 * 60).firstOrNull { it > m } ?: (6 * 60 + 24 * 60)
        val k = now.clone() as Calendar
        k.set(Calendar.HOUR_OF_DAY, 0); k.set(Calendar.MINUTE, 0); k.set(Calendar.SECOND, 5); k.set(Calendar.MILLISECOND, 0)
        k.add(Calendar.MINUTE, next)
        return k.timeInMillis
    }

    fun enabled(c: Context) = Store.config(c).optBoolean("iconSwitching", true)

    /** Apply the right icon now. Skipped while LifeMode is on screen (some
     *  launchers close the app when its launcher component changes). */
    fun apply(c: Context, force: Boolean = false) {
        if (appVisible && !force) { Store.prefs(c).edit().putBoolean("iconPending", true).apply(); return }
        val want = if (enabled(c)) variantAt(Store.minuteOfDay()) else DEFAULT
        val p = Store.prefs(c)
        if (p.getString("icon", DEFAULT) == want && !force) return
        val pm = c.packageManager
        // Enable the new alias first so the app always has a launcher entry.
        for ((v, cls) in aliases.sortedBy { if (it.first == want) 0 else 1 }) {
            val state = if (v == want) PackageManager.COMPONENT_ENABLED_STATE_ENABLED else PackageManager.COMPONENT_ENABLED_STATE_DISABLED
            try { pm.setComponentEnabledSetting(ComponentName(c.packageName, "${c.packageName}.$cls"), state, PackageManager.DONT_KILL_APP) } catch (_: Exception) {}
        }
        p.edit().putString("icon", want).putBoolean("iconPending", false).apply()
    }

    fun current(c: Context) = Store.prefs(c).getString("icon", DEFAULT) ?: DEFAULT

    fun schedule(c: Context) {
        val delay = (nextSwitchMs() - System.currentTimeMillis()).coerceAtLeast(60_000)
        val req = OneTimeWorkRequestBuilder<IconWorker>().setInitialDelay(delay, TimeUnit.MILLISECONDS).build()
        try { WorkManager.getInstance(c).enqueueUniqueWork("lifemode_icon", ExistingWorkPolicy.REPLACE, req) } catch (_: Exception) {}
    }
}

class IconWorker(ctx: Context, params: WorkerParameters) : Worker(ctx, params) {
    override fun doWork(): Result {
        IconSwitcher.apply(applicationContext)
        IconSwitcher.schedule(applicationContext)
        // Keep the context service alive (WorkManager doubles as a watchdog).
        val cfg = Store.config(applicationContext)
        if (cfg.optBoolean("onboarded", false) && cfg.optBoolean("engineOn", true) && !Live.serviceRunning) {
            try { ContextService.start(applicationContext) } catch (_: Exception) {}
        }
        return Result.success()
    }
}
