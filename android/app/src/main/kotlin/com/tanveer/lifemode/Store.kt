package com.tanveer.lifemode

import android.content.Context
import android.content.SharedPreferences
import org.json.JSONArray
import org.json.JSONObject
import java.util.Calendar

/** Native-side storage. The config JSON is written by the Flutter UI and read
 *  here so the foreground service works without the UI running. */
object Store {
    private const val FILE = "lifemode_native"
    fun prefs(c: Context): SharedPreferences = c.applicationContext.getSharedPreferences(FILE, Context.MODE_PRIVATE)

    fun configJson(c: Context): String = prefs(c).getString("config", "") ?: ""
    fun config(c: Context): JSONObject = try { JSONObject(configJson(c).ifEmpty { "{}" }) } catch (e: Exception) { JSONObject() }
    fun saveConfig(c: Context, json: String) = prefs(c).edit().putString("config", json).apply()

    fun updateConfig(c: Context, block: (JSONObject) -> Unit) {
        val j = config(c); block(j); saveConfig(c, j.toString())
    }

    fun lang(c: Context) = config(c).optString("lang", "hi")
    fun hi(c: Context) = lang(c) != "en"
    fun s(c: Context, hinglish: String, english: String) = if (hi(c)) hinglish else english

    fun sensor(cfg: JSONObject, key: String): Boolean {
        val s = cfg.optJSONObject("sensors")
        val def = key != "mic"
        return s?.optBoolean(key, def) ?: def
    }

    fun strList(cfg: JSONObject, key: String, def: List<String> = emptyList()): List<String> {
        val a: JSONArray = cfg.optJSONArray(key) ?: return def
        return (0 until a.length()).map { a.optString(it) }.filter { it.isNotBlank() }
    }

    fun incognitoUntil(cfg: JSONObject) = cfg.optLong("incognitoUntilMs", 0L)
    fun engineOn(c: Context) = config(c).optBoolean("engineOn", true)

    /** Override mode for [minutes] (0 = clear). */
    fun setOverride(c: Context, mode: String, minutes: Int) = updateConfig(c) {
        if (minutes <= 0) { it.put("overrideMode", ""); it.put("overrideUntilMs", 0) }
        else { it.put("overrideMode", mode); it.put("overrideUntilMs", System.currentTimeMillis() + minutes * 60_000L) }
    }

    fun setOverrideUntil(c: Context, mode: String, untilMs: Long) = updateConfig(c) {
        it.put("overrideMode", mode); it.put("overrideUntilMs", untilMs)
    }

    // ---- focus counters (per day) ----
    private fun dayKey(): String { val k = Calendar.getInstance(); return "${k.get(Calendar.YEAR)}-${k.get(Calendar.DAY_OF_YEAR)}" }
    fun addFocus(c: Context, studySec: Long, distractedSec: Long) {
        val p = prefs(c); val day = dayKey()
        val e = p.edit()
        if (p.getString("focusDay", "") != day) { e.putString("focusDay", day); e.putLong("focusStudy", 0); e.putLong("focusDistracted", 0) }
        val base = if (p.getString("focusDay", "") == day) p else null
        e.putLong("focusStudy", (base?.getLong("focusStudy", 0) ?: 0) + studySec)
        e.putLong("focusDistracted", (base?.getLong("focusDistracted", 0) ?: 0) + distractedSec)
        e.apply()
    }
    fun focus(c: Context): Pair<Long, Long> {
        val p = prefs(c)
        if (p.getString("focusDay", "") != dayKey()) return 0L to 0L
        return p.getLong("focusStudy", 0) to p.getLong("focusDistracted", 0)
    }

    fun minuteOfDay(ms: Long = System.currentTimeMillis()): Int {
        val k = Calendar.getInstance(); k.timeInMillis = ms
        return k.get(Calendar.HOUR_OF_DAY) * 60 + k.get(Calendar.MINUTE)
    }
    fun inWindow(m: Int, start: Int, end: Int) = if (start <= end) m in start until end else m >= start || m < end

    /** Next occurrence of minute-of-day [m] after now. */
    fun nextAt(m: Int): Long {
        val k = Calendar.getInstance()
        k.set(Calendar.HOUR_OF_DAY, m / 60); k.set(Calendar.MINUTE, m % 60); k.set(Calendar.SECOND, 0); k.set(Calendar.MILLISECOND, 0)
        if (k.timeInMillis <= System.currentTimeMillis()) k.add(Calendar.DAY_OF_YEAR, 1)
        return k.timeInMillis
    }
}

/** In-process live state shared by the service, listener and UI bridge. */
object Live {
    @Volatile var mode: String = "normal"
    @Volatile var reason: String = ""
    @Volatile var manual: Boolean = false
    @Volatile var serviceRunning = false
    @Volatile var autoReplyActive = false
    @Volatile var autoReplyText = ""
    @Volatile var blockList: Set<String> = emptySet()
    @Volatile var pomodoroEndMs: Long = 0
    @Volatile var lastSnapshot: JSONObject = JSONObject()
    @Volatile var lastLat: Double? = null
    @Volatile var lastLng: Double? = null
    val allowUntil = HashMap<String, Long>()   // temporary "2 min" unblocks
    var statusSink: ((Map<String, Any?>) -> Unit)? = null

    fun status(c: Context): Map<String, Any?> {
        val (study, distracted) = Store.focus(c)
        return mapOf(
            "mode" to mode, "reason" to reason, "manual" to manual,
            "serviceRunning" to serviceRunning, "snapshot" to Json.toMap(lastSnapshot),
            "focusStudySec" to study, "focusDistractedSec" to distracted, "pomodoroEndMs" to pomodoroEndMs,
        )
    }
}

object Json {
    fun toMap(o: JSONObject): Map<String, Any?> = o.keys().asSequence().associateWith { conv(o.opt(it)) }
    private fun conv(v: Any?): Any? = when (v) {
        is JSONObject -> toMap(v)
        is JSONArray -> (0 until v.length()).map { conv(v.opt(it)) }
        JSONObject.NULL -> null
        else -> v
    }
}
