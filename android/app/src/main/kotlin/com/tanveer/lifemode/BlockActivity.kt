package com.tanveer.lifemode

import android.app.Activity
import android.content.Intent
import android.graphics.Color
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.os.Bundle
import android.util.TypedValue
import android.view.Gravity
import android.widget.Button
import android.widget.ImageView
import android.widget.LinearLayout
import android.widget.TextView

/** Full-screen "Driving Mode on" / "Padhai Mode on" shield shown when a
 *  blocked app comes to the foreground. */
class BlockActivity : Activity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        render()
    }

    override fun onNewIntent(intent: Intent) { super.onNewIntent(intent); setIntent(intent); render() }

    private fun dp(v: Int) = TypedValue.applyDimension(TypedValue.COMPLEX_UNIT_DIP, v.toFloat(), resources.displayMetrics).toInt()

    private fun render() {
        val pkg = intent.getStringExtra("pkg") ?: ""
        val mode = intent.getStringExtra("mode") ?: Live.mode
        val driving = mode == "driving"
        val label = try { packageManager.getApplicationLabel(packageManager.getApplicationInfo(pkg, 0)).toString() } catch (_: Exception) { pkg }
        val bg = if (driving) 0xFF1E1B4B.toInt() else 0xFF0F3D3E.toInt()

        val root = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL; gravity = Gravity.CENTER
            setBackgroundColor(bg); setPadding(dp(28), dp(48), dp(28), dp(48))
        }
        root.addView(ImageView(this).apply { setImageResource(R.mipmap.ic_launcher) }, LinearLayout.LayoutParams(dp(96), dp(96)))
        root.addView(TextView(this).apply {
            text = if (driving) "Driving Mode on" else Store.s(this@BlockActivity, "Padhai Mode on", "Study Mode on")
            setTextColor(Color.WHITE); textSize = 30f; typeface = Typeface.DEFAULT_BOLD; gravity = Gravity.CENTER
            setPadding(0, dp(20), 0, dp(8))
        })
        root.addView(TextView(this).apply {
            text = if (driving) Store.s(this@BlockActivity, "$label abhi blocked hai. Road pe dhyan do.",
                "$label is blocked right now. Eyes on the road.")
            else Store.s(this@BlockActivity, "$label focus ke baad. Bas thoda aur padh lo!", "$label can wait until after focus. Almost there!")
            setTextColor(0xCCFFFFFF.toInt()); textSize = 17f; gravity = Gravity.CENTER
        })
        fun btn(t: String, primary: Boolean, onClick: () -> Unit) = Button(this).apply {
            text = t; isAllCaps = false; textSize = 16f
            setTextColor(if (primary) bg else Color.WHITE)
            background = GradientDrawable().apply {
                cornerRadius = dp(28).toFloat()
                if (primary) setColor(Color.WHITE) else { setColor(Color.TRANSPARENT); setStroke(dp(1), 0x88FFFFFF.toInt()) }
            }
            setOnClickListener { onClick() }
        }
        val lp = { LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, dp(54)).apply { topMargin = dp(14) } }
        val spacer = android.view.View(this); root.addView(spacer, LinearLayout.LayoutParams(1, dp(24)))
        if (driving) {
            root.addView(btn(Store.s(this, "Google Maps kholo", "Open Google Maps"), true) {
                startActivity(Notifs.mapsIntent(this).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)); finish()
            }, lp())
            root.addView(btn(Store.s(this, "Main passenger hoon (1 ghanta)", "I'm a passenger (1 hour)"), false) {
                Store.setOverride(this, "normal", 60); Live.blockList = emptySet(); ContextService.start(this, ContextService.ACTION_TICK); finish()
            }, lp())
        } else {
            root.addView(btn(Store.s(this, "Wapas padhai pe", "Back to focus"), true) { goHome() }, lp())
            root.addView(btn(Store.s(this, "2 min ke liye kholo", "Open for 2 min"), false) {
                Live.allowUntil[pkg] = System.currentTimeMillis() + 120_000
                packageManager.getLaunchIntentForPackage(pkg)?.let { startActivity(it.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)) }
                finish()
            }, lp())
        }
        root.addView(btn(Store.s(this, "Home screen", "Home screen"), false) { goHome() }, lp())
        setContentView(root)
    }

    private fun goHome() {
        startActivity(Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_HOME).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)); finish()
    }

    @Deprecated("Back goes home, not into the blocked app")
    override fun onBackPressed() { goHome() }
}
