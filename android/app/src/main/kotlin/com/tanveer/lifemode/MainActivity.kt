package com.tanveer.lifemode

import android.Manifest
import android.annotation.SuppressLint
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.net.wifi.WifiManager
import android.os.Handler
import android.os.Looper
import androidx.core.content.ContextCompat
import androidx.core.content.FileProvider
import com.google.android.gms.location.LocationServices
import com.google.android.gms.location.Priority
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {
    private val main = Handler(Looper.getMainLooper())

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        Notifs.channels(this)
        val m = flutterEngine.dartExecutor.binaryMessenger
        EventChannel(m, "lifemode/status").setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(args: Any?, sink: EventChannel.EventSink) {
                Live.statusSink = { s -> main.post { try { sink.success(s) } catch (_: Exception) {} } }
                sink.success(Live.status(this@MainActivity))
            }
            override fun onCancel(args: Any?) { Live.statusSink = null }
        })
        MethodChannel(m, "lifemode/native").setMethodCallHandler { call, result ->
            try {
                when (call.method) {
                    "getConfig" -> result.success(Store.configJson(this))
                    "saveConfig" -> {
                        val old = Store.config(this)
                        Store.saveConfig(this, call.arguments as String)
                        val cfg = Store.config(this)
                        if (old.optBoolean("iconSwitching", true) != cfg.optBoolean("iconSwitching", true)) IconSwitcher.apply(this)
                        if (Live.serviceRunning) ContextService.start(this, ContextService.ACTION_REFRESH)
                        result.success(null)
                    }
                    "permissions" -> result.success(Perms.all(this))
                    "requestPermission" -> { Perms.request(this, call.arguments as String); result.success(null) }
                    "startService" -> { ContextService.start(this); IconSwitcher.schedule(this); result.success(null) }
                    "stopService" -> { ContextService.start(this, ContextService.ACTION_STOP); result.success(null) }
                    "status" -> result.success(Live.status(this))
                    "tickNow" -> { if (Live.serviceRunning) ContextService.start(this, ContextService.ACTION_TICK); result.success(null) }
                    "apps" -> result.success(launchableApps())
                    "currentPlace" -> currentPlace(result)
                    "startPomodoro" -> { ContextService.start(this, ContextService.ACTION_POMODORO_START, (call.arguments as? Int ?: 25).toString()); result.success(null) }
                    "stopPomodoro" -> { ContextService.start(this, ContextService.ACTION_POMODORO_STOP); result.success(null) }
                    "sendFamily" -> {
                        val text = call.argument<String>("text") ?: ""
                        startActivity(Notifs.familyIntent(this, text).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)); result.success(null)
                    }
                    "openMaps" -> { startActivity(Notifs.mapsIntent(this).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)); result.success(null) }
                    "shareFile" -> { shareFile(call.argument<String>("name") ?: "lifemode.json", call.argument<String>("text") ?: ""); result.success(null) }
                    "iconSwitching" -> { IconSwitcher.apply(this); result.success(IconSwitcher.current(this)) }
                    else -> result.notImplemented()
                }
            } catch (e: Exception) { result.error("native", e.message, null) }
        }
    }

    override fun onResume() { super.onResume(); IconSwitcher.appVisible = true }
    override fun onPause() {
        super.onPause(); IconSwitcher.appVisible = false
        if (Store.prefs(this).getBoolean("iconPending", false)) main.postDelayed({ if (!IconSwitcher.appVisible) IconSwitcher.apply(this) }, 1500)
    }

    private fun launchableApps(): List<Map<String, String>> {
        val i = Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_LAUNCHER)
        @Suppress("DEPRECATION")
        val list = packageManager.queryIntentActivities(i, 0)
        return list.map { mapOf("package" to it.activityInfo.packageName, "label" to it.loadLabel(packageManager).toString()) }
            .filter { it["package"] != packageName }.distinctBy { it["package"] }.sortedBy { it["label"]!!.lowercase() }
    }

    @SuppressLint("MissingPermission")
    private fun currentPlace(result: MethodChannel.Result) {
        @Suppress("DEPRECATION")
        val ssid = try { (applicationContext.getSystemService(WIFI_SERVICE) as WifiManager).connectionInfo?.ssid?.trim('"') ?: "" } catch (_: Exception) { "" }
        val cleanSsid = if (ssid == "<unknown ssid>") "" else ssid
        if (ContextCompat.checkSelfPermission(this, Manifest.permission.ACCESS_FINE_LOCATION) != PackageManager.PERMISSION_GRANTED) {
            result.success(mapOf("ssid" to cleanSsid)); return
        }
        var done = false
        fun finish(m: Map<String, Any?>) { if (!done) { done = true; result.success(m) } }
        main.postDelayed({ finish(mapOf("ssid" to cleanSsid)) }, 15_000)
        LocationServices.getFusedLocationProviderClient(this).getCurrentLocation(Priority.PRIORITY_HIGH_ACCURACY, null)
            .addOnSuccessListener { l -> finish(if (l == null) mapOf("ssid" to cleanSsid) else mapOf("lat" to l.latitude, "lng" to l.longitude, "ssid" to cleanSsid)) }
            .addOnFailureListener { finish(mapOf("ssid" to cleanSsid)) }
    }

    private fun shareFile(name: String, text: String) {
        val dir = File(cacheDir, "export").apply { mkdirs() }
        val f = File(dir, name); f.writeText(text)
        val uri: Uri = FileProvider.getUriForFile(this, "$packageName.files", f)
        val send = Intent(Intent.ACTION_SEND).setType("application/json").putExtra(Intent.EXTRA_STREAM, uri)
            .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        startActivity(Intent.createChooser(send, "LifeMode export"))
    }
}
