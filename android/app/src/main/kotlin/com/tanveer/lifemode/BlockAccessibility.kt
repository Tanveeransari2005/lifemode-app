package com.tanveer.lifemode

import android.accessibilityservice.AccessibilityService
import android.view.accessibility.AccessibilityEvent

/** OPTIONAL. Instant detection of blocked apps (no 1.5 s polling delay).
 *  Reads only the package name of the window that came to the front. */
class BlockAccessibility : AccessibilityService() {
    companion object { @Volatile var connected = false }
    override fun onServiceConnected() { connected = true }
    override fun onAccessibilityEvent(e: AccessibilityEvent?) {
        if (e?.eventType != AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED) return
        val pkg = e.packageName?.toString() ?: return
        if (Live.blockList.isNotEmpty()) Blocker.check(this, pkg)
    }
    override fun onInterrupt() {}
    override fun onDestroy() { connected = false; super.onDestroy() }
    override fun onUnbind(intent: android.content.Intent?): Boolean { connected = false; return super.onUnbind(intent) }
}
