package com.tanveer.lifemode

import android.content.Context
import android.os.Build
import android.util.Log
import java.io.File
import java.io.PrintWriter
import java.io.StringWriter
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

/**
 * v1.0.2: simple on-device crash log (never leaves the phone unless the user shares it).
 *  - Uncaught exceptions (any thread, UI or service) are appended to files/crash.log.
 *  - Caught-but-unexpected native failures are logged too (non-fatal lines).
 *  - A fatal crash arms "safe mode": the next launches skip auto-starting the context
 *    engine and icon switching, so the UI always opens and can show/share the log.
 */
object CrashLog {
    private const val FILE = "crash.log"
    private const val MAX_BYTES = 64 * 1024
    private const val PREFS = "lifemode_crash"
    private const val SAFE_WINDOW_MS = 30 * 60_000L
    @Volatile private var installed = false
    @Volatile private var appCtx: Context? = null

    fun install(c: Context) {
        appCtx = c.applicationContext ?: c
        if (installed) return
        installed = true
        val prev = Thread.getDefaultUncaughtExceptionHandler()
        Thread.setDefaultUncaughtExceptionHandler { t, e ->
            try {
                val ctx = appCtx
                if (ctx != null) {
                    write(ctx, "FATAL", "thread=${t.name}", e)
                    ctx.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit()
                        .putLong("lastFatalAt", System.currentTimeMillis()).commit() // sync: process is dying
                }
            } catch (_: Throwable) {}
            if (prev != null) prev.uncaughtException(t, e) else { android.os.Process.killProcess(android.os.Process.myPid()); System.exit(10) }
        }
    }

    /** Non-fatal: something we caught but should not have happened. */
    fun note(c: Context?, where: String, e: Throwable?) {
        Log.w("LifeMode", where, e)
        val ctx = c?.applicationContext ?: appCtx ?: return
        try { write(ctx, "WARN", where, e) } catch (_: Throwable) {}
    }

    fun dartError(c: Context, text: String) {
        try { write(c.applicationContext ?: c, "DART", text.take(4000), null) } catch (_: Throwable) {}
    }

    private fun file(c: Context) = File(c.filesDir, FILE)

    @Synchronized
    private fun write(c: Context, level: String, where: String, e: Throwable?) {
        val f = file(c)
        if (f.exists() && f.length() > MAX_BYTES) {
            val keep = f.readText().takeLast(MAX_BYTES / 2)
            f.writeText("…(older entries trimmed)\n$keep")
        }
        val ts = SimpleDateFormat("yyyy-MM-dd HH:mm:ss", Locale.US).format(Date())
        val sb = StringBuilder()
        sb.append("[$ts] $level $where\n")
        sb.append("  app=${appVersion(c)} android=${Build.VERSION.RELEASE} sdk=${Build.VERSION.SDK_INT} device=${Build.MANUFACTURER} ${Build.MODEL}\n")
        if (e != null) { val sw = StringWriter(); e.printStackTrace(PrintWriter(sw)); sb.append(sw.toString().lines().take(60).joinToString("\n") { "  $it" }).append('\n') }
        f.appendText(sb.toString())
    }

    private fun appVersion(c: Context): String = try {
        @Suppress("DEPRECATION") val pi = c.packageManager.getPackageInfo(c.packageName, 0)
        @Suppress("DEPRECATION") val code = if (Build.VERSION.SDK_INT >= 28) pi.longVersionCode else pi.versionCode.toLong()
        "${pi.versionName}($code)"
    } catch (_: Throwable) { "?" }

    fun read(c: Context): String = try { val f = file(c); if (f.exists()) f.readText() else "" } catch (_: Throwable) { "" }

    fun clear(c: Context) {
        try { file(c).delete() } catch (_: Throwable) {}
        exitSafeMode(c)
    }

    fun hasFatal(c: Context) = read(c).contains("] FATAL ")

    /** True right after a fatal crash, until the user taps "start engine again" (or 30 min pass). */
    fun safeMode(c: Context): Boolean {
        val p = c.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        val at = p.getLong("lastFatalAt", 0L)
        if (at == 0L) return false
        return at > p.getLong("ackAt", 0L) && System.currentTimeMillis() - at < SAFE_WINDOW_MS
    }

    fun exitSafeMode(c: Context) {
        c.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit().putLong("ackAt", System.currentTimeMillis()).apply()
    }
}
