package com.tanveer.lifemode

import android.app.Application

/** v1.0.2: installs the crash log before anything else runs, and repairs the
 *  launcher entry. Nothing here may throw. */
class LifeModeApp : Application() {
    override fun onCreate() {
        try { CrashLog.install(this) } catch (_: Throwable) {}
        super.onCreate()
        try { Migrations.run(this) } catch (t: Throwable) { CrashLog.note(this, "migrations", t) }
        try { IconSwitcher.ensureLauncher(this) } catch (t: Throwable) { CrashLog.note(this, "ensureLauncher", t) }
    }
}

object Migrations {
    /** v1.0.2: time-of-day icon switching becomes opt-in. Flipping launcher aliases makes some
     *  launchers drop the home-screen icon or close the app, so existing installs are switched
     *  off once (the user can turn it back on in Settings). Components are left as they are. */
    fun run(app: Application) {
        val p = Store.prefs(app)
        if (p.getBoolean("migrated102", false)) return
        if (Store.configJson(app).isNotEmpty()) Store.updateConfig(app) { it.put("iconSwitching", false) }
        p.edit().putBoolean("migrated102", true).putBoolean("iconPending", false).apply()
    }
}
