package com.tanveer.lifemode

import android.content.Context
import android.os.Handler
import android.os.Looper
import io.flutter.FlutterInjector
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.dart.DartExecutor
import io.flutter.plugin.common.MethodChannel

/** Headless Flutter engine running `backgroundMain` (lib/main.dart), so the
 *  context + rule engines are the same tested Dart code the app uses. */
object BgEngine {
    private var engine: FlutterEngine? = null
    private var channel: MethodChannel? = null
    @Volatile var ready = false
    private var busy = false
    private var busySince = 0L

    fun start(ctx: Context, onReady: () -> Unit) {
        if (engine != null) return
        try {
            val app = ctx.applicationContext
            val loader = FlutterInjector.instance().flutterLoader()
            if (!loader.initialized()) { loader.startInitialization(app) }
            loader.ensureInitializationComplete(app, null)
            val e = FlutterEngine(app)
            val ch = MethodChannel(e.dartExecutor.binaryMessenger, "lifemode/bg")
            ch.setMethodCallHandler { call, result ->
                if (call.method == "ready") { ready = true; result.success(null); Handler(Looper.getMainLooper()).post(onReady) }
                else result.notImplemented()
            }
            e.dartExecutor.executeDartEntrypoint(DartExecutor.DartEntrypoint(loader.findAppBundlePath(), "backgroundMain"))
            engine = e; channel = ch
        } catch (t: Throwable) {
            engine = null; channel = null; ready = false
        }
    }

    fun tick(payload: String, cb: (String?) -> Unit) {
        val ch = channel
        if (!ready || ch == null) { cb(null); return }
        val now = System.currentTimeMillis()
        if (busy && now - busySince < 15_000) { cb(null); return }
        busy = true; busySince = now
        ch.invokeMethod("tick", payload, object : MethodChannel.Result {
            override fun success(r: Any?) { busy = false; cb(r as? String) }
            override fun error(code: String, msg: String?, details: Any?) { busy = false; cb(null) }
            override fun notImplemented() { busy = false; cb(null) }
        })
    }

    fun destroy() { try { engine?.destroy() } catch (_: Exception) {}; engine = null; channel = null; ready = false }
}
