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

    /** v1.0.2: opt-in (default off). */
    fun enabled(c: Context) = Store.config(c).optBoolean("iconSwitching", false)

    private fun cn(c: Context, cls: String) = ComponentName(c.packageName, "${c.packageName}.$cls")

    /** Effective state: COMPONENT_ENABLED_STATE_DEFAULT means "as in the manifest"
     *  (only the DEFAULT alias is enabled there). */
    private fun isOn(c: Context, v: String, cls: String): Boolean {
        val st = c.packageManager.getComponentEnabledSetting(cn(c, cls))
        return st == PackageManager.COMPONENT_ENABLED_STATE_ENABLED ||
            (st == PackageManager.COMPONENT_ENABLED_STATE_DEFAULT && v == DEFAULT)
    }

    /** Guarantee the app always has a launcher entry (if every alias ended up disabled
     *  the app would vanish from the launcher and "won't open"). */
    fun ensureLauncher(c: Context) {
        if (aliases.any { (v, cls) -> try { isOn(c, v, cls) } catch (_: Exception) { true } }) return
        val pm = c.packageManager
        pm.setComponentEnabledSetting(cn(c, aliases.first { it.first == DEFAULT }.second),
            PackageManager.COMPONENT_ENABLED_STATE_ENABLED, PackageManager.DONT_KILL_APP)
        Store.prefs(c).edit().putString("icon", DEFAULT).apply()
        CrashLog.note(c, "ensureLauncher: no launcher alias was enabled, re-enabled $DEFAULT", null)
    }

    /** Apply the right icon now. Skipped while LifeMode is on screen (some
     *  launchers close the app when its launcher component changes). */
    fun apply(c: Context, force: Boolean = false) {
        try { applyInner(c, force) } catch (t: Throwable) { CrashLog.note(c, "IconSwitcher.apply", t) }
        try { ensureLauncher(c) } catch (_: Throwable) {}
    }

    private fun applyInner(c: Context, force: Boolean) {
        val p = Store.prefs(c)
        // Off (default since 1.0.2): never touch launcher components.
        if (!enabled(c)) { p.edit().putBoolean("iconPending", false).apply(); return }
        if (CrashLog.safeMode(c)) return
        if (appVisible && !force) { p.edit().putBoolean("iconPending", true).apply(); return }
        val want = variantAt(Store.minuteOfDay())
        if (p.getString("icon", DEFAULT) == want && !force) return
        val pm = c.packageManager
        val wantCls = aliases.first { it.first == want }.second
        // Enable the new alias first; only disable the others if that worked, so the
        // app always keeps a launcher entry.
        pm.setComponentEnabledSetting(cn(c, wantCls), PackageManager.COMPONENT_ENABLED_STATE_ENABLED, PackageManager.DONT_KILL_APP)
        if (!isOn(c, want, wantCls)) return
        for ((v, cls) in aliases) if (v != want) {
            try { pm.setComponentEnabledSetting(cn(c, cls), PackageManager.COMPONENT_ENABLED_STATE_DISABLED, PackageManager.DONT_KILL_APP) } catch (_: Exception) {}
        }
        p.edit().putString("icon", want).putBoolean("iconPending", false).apply()
    }

    fun current(c: Context) = Store.prefs(c).getString("icon", DEFAULT) ?: DEFAULT

    fun schedule(c: Context) {
        try {
            val delay = (nextSwitchMs() - System.currentTimeMillis()).coerceAtLeast(60_000)
            val req = OneTimeWorkRequestBuilder<IconWorker>().setInitialDelay(delay, TimeUnit.MILLISECONDS).build()
            WorkManager.getInstance(c).enqueueUniqueWork("lifemode_icon", ExistingWorkPolicy.REPLACE, req)
        } catch (t: Throwable) { CrashLog.note(c, "WorkManager.enqueue", t) }
    }
}

class IconWorker(ctx: Context, params: WorkerParameters) : Worker(ctx, params) {
    override fun doWork(): Result {
        try {
            IconSwitcher.apply(applicationContext)
            IconSwitcher.schedule(applicationContext)
            // Keep the context service alive (WorkManager doubles as a watchdog). From a worker
            // this is a background start: Android 12+ may refuse it (caught in start()).
            val cfg = Store.config(applicationContext)
            if (cfg.optBoolean("onboarded", false) && cfg.optBoolean("engineOn", true) && !Live.serviceRunning && !CrashLog.safeMode(applicationContext)) {
                ContextService.start(applicationContext)
            }
        } catch (t: Throwable) { CrashLog.note(applicationContext, "IconWorker", t) }
        return Result.success()
    }
}
