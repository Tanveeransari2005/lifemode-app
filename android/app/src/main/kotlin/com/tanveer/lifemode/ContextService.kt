package com.tanveer.lifemode

import android.Manifest
import android.annotation.SuppressLint
import android.app.AlarmManager
import android.app.NotificationManager
import android.app.Service
import android.app.usage.UsageEvents
import android.app.usage.UsageStatsManager
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.content.pm.ServiceInfo
import android.hardware.Sensor
import android.hardware.SensorEvent
import android.hardware.SensorEventListener
import android.hardware.SensorManager
import android.location.Location
import android.media.AudioFormat
import android.media.AudioRecord
import android.media.MediaRecorder
import android.net.wifi.WifiManager
import android.os.BatteryManager
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.os.VibrationEffect
import android.os.Vibrator
import android.provider.CalendarContract
import androidx.core.app.NotificationCompat
import androidx.core.app.ServiceCompat
import androidx.core.content.ContextCompat
import com.google.android.gms.location.ActivityRecognition
import com.google.android.gms.location.ActivityTransition
import com.google.android.gms.location.ActivityTransitionRequest
import com.google.android.gms.location.DetectedActivity
import com.google.android.gms.location.Geofence
import com.google.android.gms.location.GeofencingRequest
import com.google.android.gms.location.LocationCallback
import com.google.android.gms.location.LocationRequest
import com.google.android.gms.location.LocationResult
import com.google.android.gms.location.LocationServices
import com.google.android.gms.location.Priority
import org.json.JSONArray
import org.json.JSONObject
import java.util.Calendar
import kotlin.math.log10
import kotlin.math.sqrt

/**
 * The always-on foreground service. Reads context (only the sensors the user
 * enabled), asks the Dart brain (headless engine) which mode we are in, then
 * applies it: DND, app blocking, auto-reply flag, notifications.
 */
class ContextService : Service(), SensorEventListener {

    companion object {
        const val ACTION_START = "start"
        const val ACTION_STOP = "stop"
        const val ACTION_TICK = "tick"
        const val ACTION_POMODORO_START = "pomo_start"
        const val ACTION_POMODORO_STOP = "pomo_stop"
        const val ACTION_EXIT_MODE = "exit_mode"
        const val ACTION_SLEEP_NOW = "sleep_now"
        const val ACTION_INCOGNITO = "incognito"
        const val ACTION_ACTIVITY = "activity"
        const val ACTION_GEOFENCE = "geofence"
        const val ACTION_REFRESH = "refresh"
        const val TICK_MS = 20_000L
        const val POLL_MS = 1_500L

        @Volatile var instance: ContextService? = null

        /** Deliver to the running service directly (no background-FGS-start
         *  restrictions); otherwise start it. */
        fun start(c: Context, action: String = ACTION_START, extra: String = "") {
            instance?.let { svc -> svc.h.post { svc.handle(action, extra) }; return }
            val i = Intent(c, ContextService::class.java).setAction(action).putExtra("extra", extra)
            try { ContextCompat.startForegroundService(c, i) } catch (_: Exception) {}
        }
        fun stop(c: Context) = c.stopService(Intent(c, ContextService::class.java))
    }

    val h = Handler(Looper.getMainLooper())
    private var started = false

    // context state
    private var activity = ""; private var activitySince = 0L
    private var insideHome: Boolean? = null
    private var lastLoc: Location? = null
    private var speedKmh = -1.0; private var fastSamples = 0; private var slowSince = 0L
    private var screenOn = true; private var screenSince = System.currentTimeMillis()
    private var stillSince = System.currentTimeMillis(); private var lastMotion = 0f
    private var lux = -1.0; private var noiseDb = -1.0
    private var nightScreenMs = 0L; private var lastTickAt = 0L
    private var calNow = JSONArray(); private var calTomorrow = JSONArray(); private var calAt = 0L
    private var tickCount = 0
    private var currentMode = "normal"; private var modeSince = System.currentTimeMillis()
    private var lastCardKey = ""
    private var prevFilter = -1
    private var prevPolicy: NotificationManager.Policy? = null
    private var lastNudgeAt = 0L
    private var locHigh: Boolean? = null
    private var accelSamples = ArrayList<Float>()

    private val sm by lazy { getSystemService(SENSOR_SERVICE) as SensorManager }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        Notifs.channels(this)
        val p = Store.prefs(this)
        currentMode = p.getString("currentMode", "normal") ?: "normal"
        modeSince = p.getLong("modeSince", System.currentTimeMillis())
        prevFilter = p.getInt("prevFilter", -1)
        Live.pomodoroEndMs = p.getLong("pomodoroEndMs", 0)
        if (Live.pomodoroEndMs < System.currentTimeMillis()) Live.pomodoroEndMs = 0
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        goForeground()
        if (!started) { started = true; Live.serviceRunning = true; setup() }
        instance = this
        val extra = intent?.getStringExtra("extra") ?: ""
        if (intent?.action == ACTION_STOP) {
            teardown(); ServiceCompat.stopForeground(this, ServiceCompat.STOP_FOREGROUND_REMOVE); stopSelf(); return START_NOT_STICKY
        }
        handle(intent?.action ?: ACTION_TICK, extra)
        return START_STICKY
    }

    fun handle(action: String, extra: String) {
        if (action == ACTION_STOP) { stop(this); return }
        when (action) {
            ACTION_POMODORO_START -> startPomodoro(extra.toIntOrNull() ?: Store.config(this).optInt("pomodoroMin", 25))
            ACTION_POMODORO_STOP -> stopPomodoro(false)
            ACTION_EXIT_MODE -> Store.setOverride(this, "normal", 60)
            ACTION_SLEEP_NOW -> {
                val end = Store.config(this).optInt("sleepEndMin", 390)
                Store.setOverrideUntil(this, "sleep", Store.nextAt(end))
            }
            ACTION_INCOGNITO -> Store.updateConfig(this) { it.put("incognitoUntilMs", System.currentTimeMillis() + (extra.toIntOrNull() ?: 60) * 60_000L) }
            ACTION_ACTIVITY -> { if (extra != activity) { activity = extra; activitySince = System.currentTimeMillis() } }
            ACTION_GEOFENCE -> insideHome = when (extra) { "enter" -> true; "exit" -> false; else -> insideHome }
            ACTION_REFRESH -> { registerGeofence(); registerActivityTransitions(); locHigh = null; updateLocationRequest(false); lastCardKey = "" }
        }
        tick()
    }

    // ---------------------------------------------------------------- foreground
    private var cardNotif: android.app.Notification? = null

    private fun goForeground() {
        val n = cardNotif ?: Notifs.base(this, Notifs.CH_SERVICE, "LifeMode", Store.s(this, "Context dekh rahi hoon…", "Watching context…"))
            .setOngoing(true).setOnlyAlertOnce(true).setPriority(NotificationCompat.PRIORITY_LOW).build()
        val hasLoc = granted(Manifest.permission.ACCESS_FINE_LOCATION) || granted(Manifest.permission.ACCESS_COARSE_LOCATION)
        var type = 0
        if (Build.VERSION.SDK_INT >= 29) {
            type = if (hasLoc) ServiceInfo.FOREGROUND_SERVICE_TYPE_LOCATION
            else if (Build.VERSION.SDK_INT >= 34) ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE
            else ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC
        }
        try {
            ServiceCompat.startForeground(this, Notifs.ID_SERVICE, n, type)
        } catch (e: Exception) {
            // e.g. started from BOOT without background-location: run without the location type.
            val fallback = if (Build.VERSION.SDK_INT >= 34) ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE
            else if (Build.VERSION.SDK_INT >= 29) ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC else 0
            try { ServiceCompat.startForeground(this, Notifs.ID_SERVICE, n, fallback) } catch (_: Exception) {}
        }
    }

    private fun granted(p: String) = ContextCompat.checkSelfPermission(this, p) == PackageManager.PERMISSION_GRANTED

    // ---------------------------------------------------------------- setup
    private val screenRx = object : BroadcastReceiver() {
        override fun onReceive(c: Context, i: Intent) {
            val on = i.action == Intent.ACTION_SCREEN_ON || i.action == Intent.ACTION_USER_PRESENT
            if (on != screenOn) { screenOn = on; screenSince = System.currentTimeMillis() }
            if (i.action == Intent.ACTION_SCREEN_ON) onPickup()
            if (i.action != Intent.ACTION_USER_PRESENT) tick()
        }
    }

    private val locCb = object : LocationCallback() {
        override fun onLocationResult(r: LocationResult) { r.lastLocation?.let { onLocation(it) } }
    }

    private fun setup() {
        val f = IntentFilter().apply { addAction(Intent.ACTION_SCREEN_ON); addAction(Intent.ACTION_SCREEN_OFF); addAction(Intent.ACTION_USER_PRESENT) }
        ContextCompat.registerReceiver(this, screenRx, f, ContextCompat.RECEIVER_NOT_EXPORTED)
        screenOn = (getSystemService(POWER_SERVICE) as android.os.PowerManager).isInteractive
        BgEngine.start(this) { tick() }
        registerActivityTransitions()
        registerGeofence()
        updateLocationRequest(false)
        h.post(tickLoop)
        h.post(pollLoop)
        val left = Live.pomodoroEndMs - System.currentTimeMillis()
        if (left > 0) h.postDelayed(pomodoroDone, left)
        IconSwitcher.schedule(this)
    }

    private fun teardown() {
        Live.serviceRunning = false
        h.removeCallbacksAndMessages(null)
        try { unregisterReceiver(screenRx) } catch (_: Exception) {}
        try { sm.unregisterListener(this) } catch (_: Exception) {}
        try { LocationServices.getFusedLocationProviderClient(this).removeLocationUpdates(locCb) } catch (_: Exception) {}
        exitMode(currentMode)
        Live.autoReplyActive = false; Live.blockList = emptySet()
        pushStatus()
    }

    override fun onDestroy() { if (Live.serviceRunning) teardown(); instance = null; super.onDestroy() }

    @SuppressLint("MissingPermission")
    private fun registerActivityTransitions() {
        val ok = if (Build.VERSION.SDK_INT >= 29) granted(Manifest.permission.ACTIVITY_RECOGNITION) else true
        if (!ok || !Store.sensor(Store.config(this), "activity")) return
        val types = listOf(DetectedActivity.IN_VEHICLE, DetectedActivity.ON_BICYCLE, DetectedActivity.WALKING, DetectedActivity.RUNNING, DetectedActivity.STILL)
        val list = types.flatMap { t ->
            listOf(ActivityTransition.ACTIVITY_TRANSITION_ENTER, ActivityTransition.ACTIVITY_TRANSITION_EXIT).map {
                ActivityTransition.Builder().setActivityType(t).setActivityTransition(it).build()
            }
        }
        try {
            ActivityRecognition.getClient(this).requestActivityTransitionUpdates(ActivityTransitionRequest(list), Receivers.activityPi(this))
        } catch (_: Exception) {}
    }

    @SuppressLint("MissingPermission")
    private fun registerGeofence() {
        val cfg = Store.config(this)
        if (!cfg.has("homeLat") || cfg.isNull("homeLat") || !Store.sensor(cfg, "location")) return
        val bgOk = Build.VERSION.SDK_INT < 29 || granted(Manifest.permission.ACCESS_BACKGROUND_LOCATION)
        if (!granted(Manifest.permission.ACCESS_FINE_LOCATION) || !bgOk) return
        val fence = Geofence.Builder().setRequestId("home")
            .setCircularRegion(cfg.optDouble("homeLat"), cfg.optDouble("homeLng"), cfg.optInt("homeRadiusM", 150).toFloat().coerceAtLeast(100f))
            .setExpirationDuration(Geofence.NEVER_EXPIRE)
            .setTransitionTypes(Geofence.GEOFENCE_TRANSITION_ENTER or Geofence.GEOFENCE_TRANSITION_EXIT)
            .setLoiteringDelay(60_000).build()
        val req = GeofencingRequest.Builder().setInitialTrigger(GeofencingRequest.INITIAL_TRIGGER_ENTER).addGeofence(fence).build()
        try {
            val client = LocationServices.getGeofencingClient(this)
            client.removeGeofences(Receivers.geofencePi(this)).addOnCompleteListener { client.addGeofences(req, Receivers.geofencePi(this)) }
        } catch (_: Exception) {}
    }

    @SuppressLint("MissingPermission")
    private fun updateLocationRequest(high: Boolean) {
        if (locHigh == high) return
        val cfg = Store.config(this)
        if (!Store.sensor(cfg, "location") || !(granted(Manifest.permission.ACCESS_FINE_LOCATION) || granted(Manifest.permission.ACCESS_COARSE_LOCATION))) return
        locHigh = high
        val req = if (high) LocationRequest.Builder(Priority.PRIORITY_HIGH_ACCURACY, 5_000).setMinUpdateIntervalMillis(3_000).build()
        else LocationRequest.Builder(Priority.PRIORITY_BALANCED_POWER_ACCURACY, 60_000).setMinUpdateIntervalMillis(20_000).build()
        try {
            val c = LocationServices.getFusedLocationProviderClient(this)
            c.removeLocationUpdates(locCb)
            c.requestLocationUpdates(req, locCb, Looper.getMainLooper())
        } catch (_: Exception) {}
    }

    private fun onLocation(l: Location) {
        val prev = lastLoc
        var v = if (l.hasSpeed()) l.speed * 3.6 else -1.0
        if (v < 0 && prev != null && l.accuracy < 80 && l.time > prev.time) {
            v = prev.distanceTo(l) / ((l.time - prev.time) / 1000.0) * 3.6
        }
        lastLoc = l; Live.lastLat = l.latitude; Live.lastLng = l.longitude
        speedKmh = v
        val drive = Store.config(this).optInt("drivingSpeedKmh", 20)
        fastSamples = if (v >= drive) fastSamples + 1 else 0
        if (v in 0.0..8.0) { if (slowSince == 0L) slowSince = System.currentTimeMillis() } else slowSince = 0L
        if (System.currentTimeMillis() - lastTickAt > 45_000) tick()
    }

    // ---------------------------------------------------------------- sensors
    private fun sampleSensors(cfg: JSONObject) {
        if (Store.sensor(cfg, "motion")) sm.getDefaultSensor(Sensor.TYPE_ACCELEROMETER)?.let { sm.registerListener(this, it, SensorManager.SENSOR_DELAY_NORMAL) }
        if (Store.sensor(cfg, "light")) sm.getDefaultSensor(Sensor.TYPE_LIGHT)?.let { sm.registerListener(this, it, SensorManager.SENSOR_DELAY_NORMAL) }
        h.postDelayed({ try { sm.unregisterListener(this) } catch (_: Exception) {}; evalMotion() }, 2_500)
    }

    override fun onSensorChanged(e: SensorEvent) {
        when (e.sensor.type) {
            Sensor.TYPE_LIGHT -> lux = e.values[0].toDouble()
            Sensor.TYPE_ACCELEROMETER -> {
                val (x, y, z) = Triple(e.values[0], e.values[1], e.values[2])
                accelSamples.add(sqrt(x * x + y * y + z * z))
            }
        }
    }

    private fun evalMotion() {
        if (accelSamples.size < 3) { accelSamples.clear(); return }
        val mean = accelSamples.average()
        val variance = accelSamples.map { (it - mean) * (it - mean) }.average()
        accelSamples.clear()
        lastMotion = variance.toFloat()
        if (variance > 0.05) stillSince = System.currentTimeMillis()
    }

    override fun onAccuracyChanged(s: Sensor?, a: Int) {}

    /** Loudness only: reads 0.5 s of audio into memory, keeps one number, discards samples. Never records. */
    @SuppressLint("MissingPermission")
    private fun sampleNoise() {
        if (!granted(Manifest.permission.RECORD_AUDIO)) return
        Thread {
            var rec: AudioRecord? = null
            try {
                val rate = 16000
                val size = AudioRecord.getMinBufferSize(rate, AudioFormat.CHANNEL_IN_MONO, AudioFormat.ENCODING_PCM_16BIT).coerceAtLeast(8000)
                rec = AudioRecord(MediaRecorder.AudioSource.MIC, rate, AudioFormat.CHANNEL_IN_MONO, AudioFormat.ENCODING_PCM_16BIT, size)
                val buf = ShortArray(size / 2)
                rec.startRecording()
                var sum = 0.0; var n = 0
                val until = System.currentTimeMillis() + 500
                while (System.currentTimeMillis() < until) {
                    val r = rec.read(buf, 0, buf.size)
                    for (i in 0 until r.coerceAtLeast(0)) { sum += buf[i] * buf[i].toDouble(); n++ }
                }
                val rms = if (n > 0) sqrt(sum / n) else 0.0
                noiseDb = if (rms > 0) 20 * log10(rms) else 0.0
            } catch (_: Exception) { noiseDb = -1.0 } finally { try { rec?.stop(); rec?.release() } catch (_: Exception) {} }
        }.start()
    }

    // ---------------------------------------------------------------- readers
    @Suppress("DEPRECATION")
    private fun wifiSsid(): String = try {
        val wm = applicationContext.getSystemService(WIFI_SERVICE) as WifiManager
        val s = wm.connectionInfo?.ssid ?: ""
        if (s == "<unknown ssid>") "" else s.trim('"')
    } catch (_: Exception) { "" }

    private fun battery(): Pair<Int, Boolean> {
        val i = registerReceiver(null, IntentFilter(Intent.ACTION_BATTERY_CHANGED)) ?: return 100 to false
        val level = i.getIntExtra(BatteryManager.EXTRA_LEVEL, 100); val scale = i.getIntExtra(BatteryManager.EXTRA_SCALE, 100)
        val plugged = i.getIntExtra(BatteryManager.EXTRA_PLUGGED, 0) != 0
        return (level * 100 / scale.coerceAtLeast(1)) to plugged
    }

    private fun readCalendar() {
        if (!granted(Manifest.permission.READ_CALENDAR)) return
        val now = System.currentTimeMillis()
        val k = Calendar.getInstance(); k.add(Calendar.DAY_OF_YEAR, 1)
        k.set(Calendar.HOUR_OF_DAY, 0); k.set(Calendar.MINUTE, 0); k.set(Calendar.SECOND, 0); k.set(Calendar.MILLISECOND, 0)
        val tStart = k.timeInMillis; val tEnd = tStart + 24 * 3600_000L
        calNow = queryInstances(now - 12 * 3600_000L, now + 3600_000L).let { a ->
            JSONArray().also { out -> for (i in 0 until a.length()) { val e = a.getJSONObject(i); if (e.getLong("endMs") > now) out.put(e) } }
        }
        calTomorrow = queryInstances(tStart, tEnd)
        calAt = now
    }

    private fun queryInstances(from: Long, to: Long): JSONArray {
        val out = JSONArray()
        try {
            val uri = CalendarContract.Instances.CONTENT_URI.buildUpon().appendPath(from.toString()).appendPath(to.toString()).build()
            contentResolver.query(uri, arrayOf(CalendarContract.Instances.TITLE, CalendarContract.Instances.BEGIN, CalendarContract.Instances.END, CalendarContract.Instances.ALL_DAY),
                null, null, CalendarContract.Instances.BEGIN + " ASC")?.use { c ->
                while (c.moveToNext() && out.length() < 20) {
                    if (c.getInt(3) == 1) continue // skip all-day (holidays, birthdays)
                    out.put(JSONObject().put("title", c.getString(0) ?: "").put("beginMs", c.getLong(1)).put("endMs", c.getLong(2)))
                }
            }
        } catch (_: Exception) {}
        return out
    }

    private fun usageOk(): Boolean = Perms.usage(this)

    /** (foreground package, app switches in the last 10 min) from UsageStats. */
    private fun usage(windowMs: Long = 600_000L): Pair<String, Int> {
        if (!usageOk()) return "" to 0
        val um = getSystemService(USAGE_STATS_SERVICE) as UsageStatsManager
        val now = System.currentTimeMillis()
        val ev = um.queryEvents(now - windowMs, now)
        val e = UsageEvents.Event()
        var last = ""; var switches = 0
        val resumed = if (Build.VERSION.SDK_INT >= 29) UsageEvents.Event.ACTIVITY_RESUMED else @Suppress("DEPRECATION") UsageEvents.Event.MOVE_TO_FOREGROUND
        while (ev.hasNextEvent()) {
            ev.getNextEvent(e)
            if (e.eventType == resumed && e.packageName != last) { if (last.isNotEmpty()) switches++; last = e.packageName }
        }
        return last to switches
    }

    // ---------------------------------------------------------------- tick
    private val tickLoop = object : Runnable { override fun run() { tick(); h.postDelayed(this, TICK_MS) } }

    private fun tick() {
        val cfg = Store.config(this)
        val now = System.currentTimeMillis()
        val dt = if (lastTickAt == 0L) 0L else (now - lastTickAt).coerceIn(0, 120_000)
        lastTickAt = now
        val incognito = Store.incognitoUntil(cfg) > now
        val snap = JSONObject()
        snap.put("nowMs", now)
        snap.put("screenOn", screenOn)
        snap.put("screenOffForSec", if (screenOn) 0 else (now - screenSince) / 1000)
        snap.put("screenOnForSec", if (screenOn) (now - screenSince) / 1000 else 0)
        val (bat, plugged) = battery()
        snap.put("batteryPct", bat); snap.put("charging", plugged)
        snap.put("currentMode", currentMode); snap.put("currentModeSinceMs", modeSince)
        snap.put("pomodoroRunning", Live.pomodoroEndMs > now)

        if (!incognito) {
            tickCount++
            sampleSensors(cfg)
            if (Store.sensor(cfg, "mic") && tickCount % 6 == 0) sampleNoise()
            if (Store.sensor(cfg, "calendar") && now - calAt > 5 * 60_000L) readCalendar()
            snap.put("speedKmh", if (Store.sensor(cfg, "location")) speedKmh else -1.0)
            snap.put("fastSamples", fastSamples)
            snap.put("slowForSec", if (slowSince == 0L) 0 else (now - slowSince) / 1000)
            snap.put("activity", if (Store.sensor(cfg, "activity")) activity else "")
            snap.put("activitySinceMs", activitySince)
            insideHome?.let { snap.put("insideHome", it) }
            val loc = lastLoc
            if (loc != null && cfg.has("homeLat") && !cfg.isNull("homeLat") && Store.sensor(cfg, "location")) {
                val r = FloatArray(1)
                Location.distanceBetween(loc.latitude, loc.longitude, cfg.optDouble("homeLat"), cfg.optDouble("homeLng"), r)
                snap.put("distanceHomeM", r[0].toDouble())
            }
            if (Store.sensor(cfg, "wifi")) snap.put("wifiSsid", wifiSsid())
            snap.put("stationaryForSec", if (Store.sensor(cfg, "motion")) (now - stillSince) / 1000 else 0)
            snap.put("lux", if (Store.sensor(cfg, "light")) lux else -1.0)
            snap.put("noiseDb", if (Store.sensor(cfg, "mic")) noiseDb else -1.0)
            if (Store.sensor(cfg, "calendar")) { snap.put("calendarNow", calNow); snap.put("calendarTomorrow", calTomorrow) }
            val alarm = (getSystemService(ALARM_SERVICE) as AlarmManager).nextAlarmClock?.triggerTime ?: 0L
            snap.put("nextAlarmMs", alarm)
            if (Store.sensor(cfg, "usage")) {
                val (fg, switches) = usage()
                snap.put("foregroundApp", fg); snap.put("appSwitches10m", switches)
                if (currentMode == "study" && dt > 0) {
                    val distracted = if (fg in Store.strList(cfg, "blockStudy") && screenOn) dt else 0L
                    Store.addFocus(this, dt / 1000, distracted / 1000)
                }
            }
            // screen-on minutes inside the night window (late-night scrolling)
            val inNight = Store.inWindow(Store.minuteOfDay(now), cfg.optInt("sleepStartMin", 1380), cfg.optInt("sleepEndMin", 390))
            nightScreenMs = if (!inNight) 0 else if (screenOn) nightScreenMs + dt else nightScreenMs
            snap.put("nightScreenMin", nightScreenMs / 60_000)
            // GPS power: high accuracy only when we may be moving in a vehicle.
            updateLocationRequest(activity == "IN_VEHICLE" || currentMode == "driving" || speedKmh > 12)
        }
        if (!screenOn) keepTickingWhileIdle()
        Live.lastSnapshot = snap
        val payload = JSONObject().put("snapshot", snap).put("config", cfg).toString()
        BgEngine.tick(payload) { res -> if (res != null) apply(JSONObject(res), cfg) else pushStatus() }
    }

    /** With the screen off the CPU sleeps and Handler ticks stop; a while-idle
     *  alarm (max ~every 9 min in Doze) + a 4 s wakelock keep Sleep/Home detection alive. */
    private fun keepTickingWhileIdle() {
        try {
            val pm = getSystemService(POWER_SERVICE) as android.os.PowerManager
            pm.newWakeLock(android.os.PowerManager.PARTIAL_WAKE_LOCK, "lifemode:tick").acquire(4_000)
            val am = getSystemService(ALARM_SERVICE) as AlarmManager
            val pi = android.app.PendingIntent.getBroadcast(this, 21, Intent(this, TickRx::class.java),
                android.app.PendingIntent.FLAG_UPDATE_CURRENT or android.app.PendingIntent.FLAG_IMMUTABLE)
            am.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, System.currentTimeMillis() + 10 * 60_000L, pi)
        } catch (_: Exception) {}
    }

    // ---------------------------------------------------------------- apply
    private fun apply(r: JSONObject, cfg: JSONObject) {
        val mode = r.optString("mode", "normal")
        Live.reason = r.optString("reason"); Live.manual = r.optBoolean("manual")
        if (mode != currentMode) {
            exitMode(currentMode)
            currentMode = mode; modeSince = System.currentTimeMillis()
            Store.prefs(this).edit().putString("currentMode", mode).putLong("modeSince", modeSince).apply()
            enterMode(mode, r, cfg)
        }
        Live.mode = mode
        Live.blockList = when (mode) {
            "driving" -> Store.strList(cfg, "blockDriving").toSet()
            "study" -> Store.strList(cfg, "blockStudy").toSet()
            else -> emptySet()
        }
        Live.autoReplyActive = mode == "driving" && cfg.optBoolean("autoReply", true)
        Live.autoReplyText = cfg.optString("autoReplyText", "Main drive kar rahi hoon, baad me baat karti hoon.")
        updateCard(r, cfg)
        r.optJSONObject("suggestion")?.let { showSuggestion(it) }
        pushStatus()
    }

    private fun enterMode(mode: String, r: JSONObject, cfg: JSONObject) {
        when (mode) {
            "driving", "sleep" -> setDnd(true)
            "home" -> {
                val lines = r.optJSONArray("lines")
                val text = r.optString("body") + (if (lines != null && lines.length() > 0) "\n" + (0 until lines.length()).joinToString("\n") { "• " + lines.optString(it) } else "")
                val msg = if (Store.hi(this)) "Main ghar pahunch gayi" else "I reached home"
                val b = Notifs.base(this, Notifs.CH_ALERT, r.optString("title"), text).setAutoCancel(true)
                    .addAction(0, Store.s(this, "${cfg.optString("familyName", "Family")} ko bhejo", "Send to ${cfg.optString("familyName", "family")}"),
                        Notifs.activity(this, Notifs.familyIntent(this, msg)))
                Notifs.post(this, Notifs.ID_ALERT, b)
            }
        }
    }

    private fun exitMode(mode: String) {
        when (mode) {
            "driving", "sleep" -> setDnd(false)
            "study" -> if (Live.pomodoroEndMs > System.currentTimeMillis()) { /* keep timer running */ }
        }
    }

    private fun setDnd(on: Boolean) {
        val nm = getSystemService(NOTIFICATION_SERVICE) as NotificationManager
        if (Build.VERSION.SDK_INT < 23 || !nm.isNotificationPolicyAccessGranted) return
        val p = Store.prefs(this)
        try {
            if (on) {
                if (nm.currentInterruptionFilter == NotificationManager.INTERRUPTION_FILTER_PRIORITY && p.getBoolean("dndOurs", false)) return
                prevFilter = nm.currentInterruptionFilter
                prevPolicy = nm.notificationPolicy
                var cats = NotificationManager.Policy.PRIORITY_CATEGORY_CALLS or NotificationManager.Policy.PRIORITY_CATEGORY_REPEAT_CALLERS
                if (Build.VERSION.SDK_INT >= 28) cats = cats or NotificationManager.Policy.PRIORITY_CATEGORY_ALARMS
                nm.notificationPolicy = NotificationManager.Policy(cats, NotificationManager.Policy.PRIORITY_SENDERS_STARRED, NotificationManager.Policy.PRIORITY_SENDERS_STARRED)
                nm.setInterruptionFilter(NotificationManager.INTERRUPTION_FILTER_PRIORITY)
                p.edit().putInt("prevFilter", prevFilter).putBoolean("dndOurs", true).apply()
            } else if (p.getBoolean("dndOurs", false)) {
                prevPolicy?.let { nm.notificationPolicy = it }
                val restore = p.getInt("prevFilter", NotificationManager.INTERRUPTION_FILTER_ALL)
                nm.setInterruptionFilter(if (restore > 0) restore else NotificationManager.INTERRUPTION_FILTER_ALL)
                p.edit().putBoolean("dndOurs", false).apply()
            }
        } catch (_: Exception) {}
    }

    private fun updateCard(r: JSONObject, cfg: JSONObject) {
        val mode = r.optString("mode")
        val lines = r.optJSONArray("lines")
        val key = mode + r.optString("reason") + r.optString("title") + lines.toString() + Live.pomodoroEndMs
        if (key == lastCardKey) return
        lastCardKey = key
        val body = r.optString("body")
        val big = StringBuilder(body)
        if (lines != null) for (i in 0 until lines.length()) big.append("\n• ").append(lines.optString(i))
        val b = Notifs.base(this, Notifs.CH_SERVICE, r.optString("title"), body)
            .setSubText(Store.s(this, "Kyun: ", "Why: ") + r.optString("reason"))
            .setStyle(NotificationCompat.BigTextStyle().bigText(big.toString()))
            .setOngoing(true).setOnlyAlertOnce(true).setPriority(NotificationCompat.PRIORITY_LOW)
        val notMe = Store.s(this, "Ye mode nahi", "Not this mode")
        when (mode) {
            "driving" -> {
                b.addAction(0, Store.s(this, "Google Maps kholo", "Open Google Maps"), Notifs.activity(this, Notifs.mapsIntent(this)))
                b.addAction(0, Store.s(this, "Main passenger hoon", "I'm a passenger"), Notifs.serviceAction(this, ACTION_EXIT_MODE))
            }
            "study" -> {
                if (Live.pomodoroEndMs > System.currentTimeMillis()) {
                    b.setUsesChronometer(true).setWhen(Live.pomodoroEndMs).setShowWhen(true)
                    if (Build.VERSION.SDK_INT >= 24) b.setChronometerCountDown(true)
                    b.addAction(0, Store.s(this, "Timer roko", "Stop timer"), Notifs.serviceAction(this, ACTION_POMODORO_STOP))
                } else {
                    val m = cfg.optInt("pomodoroMin", 25)
                    b.addAction(0, Store.s(this, "$m min focus", "$m min focus"), Notifs.serviceAction(this, ACTION_POMODORO_START, m.toString()))
                }
                b.addAction(0, notMe, Notifs.serviceAction(this, ACTION_EXIT_MODE))
            }
            "sleep" -> b.addAction(0, Store.s(this, "Main jaag rahi hoon", "I'm awake"), Notifs.serviceAction(this, ACTION_EXIT_MODE))
            "home" -> b.addAction(0, Store.s(this, "Ghar pahunch gayi bhejo", "Tell family I'm home"),
                Notifs.activity(this, Notifs.familyIntent(this, if (Store.hi(this)) "Main ghar pahunch gayi" else "I reached home")))
            else -> {
                b.addAction(0, Store.s(this, "Incognito 1 ghanta", "Incognito 1 h"), Notifs.serviceAction(this, ACTION_INCOGNITO, "60"))
                b.addAction(0, Store.s(this, "Sleep ab", "Sleep now"), Notifs.serviceAction(this, ACTION_SLEEP_NOW))
            }
        }
        cardNotif = b.build()
        Notifs.post(this, Notifs.ID_SERVICE, b)
    }

    private fun showSuggestion(s: JSONObject) {
        val b = Notifs.base(this, Notifs.CH_SUGGEST, s.optString("title"), s.optString("body")).setAutoCancel(true)
        when (s.optString("action")) {
            "battery_saver_share" -> {
                b.addAction(0, Store.s(this, "Power saving", "Power saving"), Notifs.activity(this, Notifs.batterySaverIntent()))
                b.addAction(0, Store.s(this, "Location share", "Share location"), Notifs.activity(this, Notifs.familyIntent(this, Notifs.locationText(this))))
            }
            "sleep_now" -> b.addAction(0, Store.s(this, "Haan, Sleep mode", "Yes, Sleep mode"), Notifs.serviceAction(this, ACTION_SLEEP_NOW))
            "start_focus" -> b.addAction(0, Store.s(this, "Focus shuru", "Start focus"), Notifs.serviceAction(this, ACTION_POMODORO_START))
            "send_late_msg" -> b.addAction(0, Store.s(this, "Update bhejo", "Send update"),
                Notifs.activity(this, Notifs.familyIntent(this, Store.s(this, "Aaj thoda late ho jayega, jaldi aati hoon.", "Running a bit late today, will be home soon."))))
            "set_alarm" -> b.addAction(0, Store.s(this, "Alarm lagao", "Set alarm"), Notifs.activity(this, Notifs.setAlarmIntent()))
        }
        Notifs.post(this, Notifs.ID_SUGGEST, b)
    }

    // ---------------------------------------------------------------- study
    private fun startPomodoro(min: Int) {
        Live.pomodoroEndMs = System.currentTimeMillis() + min * 60_000L
        Store.prefs(this).edit().putLong("pomodoroEndMs", Live.pomodoroEndMs).apply()
        h.removeCallbacks(pomodoroDone)
        h.postDelayed(pomodoroDone, min * 60_000L)
        lastCardKey = ""
    }

    private fun stopPomodoro(done: Boolean) {
        Live.pomodoroEndMs = 0
        Store.prefs(this).edit().putLong("pomodoroEndMs", 0).apply()
        h.removeCallbacks(pomodoroDone)
        lastCardKey = ""
        if (done) {
            vibrate(longArrayOf(0, 200, 120, 200))
            Notifs.post(this, Notifs.ID_ALERT, Notifs.base(this, Notifs.CH_ALERT,
                Store.s(this, "Focus session done!", "Focus session done!"),
                Store.s(this, "Shabash. 5 min break lo, paani piyo.", "Well done. Take a 5 min break, drink water.")).setAutoCancel(true))
        }
    }

    private val pomodoroDone = Runnable { stopPomodoro(true); tick() }

    private fun onPickup() {
        val now = System.currentTimeMillis()
        if ((currentMode != "study" && Live.pomodoroEndMs <= now) || now - lastNudgeAt < 5 * 60_000L) return
        lastNudgeAt = now
        vibrate(longArrayOf(0, 60))
        val left = if (Live.pomodoroEndMs > now) " (${(Live.pomodoroEndMs - now) / 60_000 + 1} min)" else ""
        Notifs.post(this, Notifs.ID_NUDGE, Notifs.base(this, Notifs.CH_SUGGEST,
            Store.s(this, "Padhai chal rahi hai$left", "Focus is on$left"),
            Store.s(this, "Phone side me rakho, bas thoda aur.", "Put the phone aside, almost there.")).setAutoCancel(true).setTimeoutAfter(60_000))
    }

    fun vibrate(pattern: LongArray) {
        try {
            @Suppress("DEPRECATION")
            val v = getSystemService(VIBRATOR_SERVICE) as Vibrator
            if (Build.VERSION.SDK_INT >= 26) v.vibrate(VibrationEffect.createWaveform(pattern, -1)) else @Suppress("DEPRECATION") v.vibrate(pattern, -1)
        } catch (_: Exception) {}
    }

    // ---------------------------------------------------------------- blocking
    private val pollLoop = object : Runnable {
        override fun run() {
            if (Live.blockList.isNotEmpty() && screenOn && !BlockAccessibility.connected) {
                val (fg, _) = usage(60_000L)
                checkBlocked(this@ContextService, fg)
            }
            h.postDelayed(this, POLL_MS)
        }
    }

    private fun checkBlocked(c: Context, pkg: String) = Blocker.check(c, pkg)

    private fun pushStatus() { val s = Live.status(this); h.post { Live.statusSink?.invoke(s) } }
}

/** Shared by the poll loop and the optional AccessibilityService. */
object Blocker {
    private var lastAt = 0L
    private var lastPkg = ""
    fun check(c: Context, pkg: String) {
        if (pkg.isEmpty() || pkg == c.packageName || pkg !in Live.blockList) return
        val now = System.currentTimeMillis()
        if ((Live.allowUntil[pkg] ?: 0L) > now) return
        if (pkg == lastPkg && now - lastAt < 2_500) return
        lastPkg = pkg; lastAt = now
        val i = Intent(c, BlockActivity::class.java)
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_NO_ANIMATION)
            .putExtra("pkg", pkg).putExtra("mode", Live.mode)
        try { c.startActivity(i) } catch (_: Exception) {}
    }
}
