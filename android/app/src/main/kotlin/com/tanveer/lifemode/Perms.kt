package com.tanveer.lifemode

import android.Manifest
import android.app.Activity
import android.app.AppOpsManager
import android.app.NotificationManager
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.PowerManager
import android.os.Process
import android.provider.Settings
import androidx.core.app.ActivityCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.ContextCompat

object Perms {
    private fun g(c: Context, p: String) = ContextCompat.checkSelfPermission(c, p) == PackageManager.PERMISSION_GRANTED

    fun usage(c: Context): Boolean {
        val ops = c.getSystemService(Context.APP_OPS_SERVICE) as AppOpsManager
        @Suppress("DEPRECATION")
        val mode = if (Build.VERSION.SDK_INT >= 29) ops.unsafeCheckOpNoThrow(AppOpsManager.OPSTR_GET_USAGE_STATS, Process.myUid(), c.packageName)
        else ops.checkOpNoThrow(AppOpsManager.OPSTR_GET_USAGE_STATS, Process.myUid(), c.packageName)
        return mode == AppOpsManager.MODE_ALLOWED
    }

    fun all(c: Context): Map<String, Boolean> {
        val nm = c.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        val pm = c.getSystemService(Context.POWER_SERVICE) as PowerManager
        val acc = Settings.Secure.getString(c.contentResolver, Settings.Secure.ENABLED_ACCESSIBILITY_SERVICES) ?: ""
        return mapOf(
            "notifications" to NotificationManagerCompat.from(c).areNotificationsEnabled(),
            "location" to g(c, Manifest.permission.ACCESS_FINE_LOCATION),
            "backgroundLocation" to (Build.VERSION.SDK_INT < 29 || g(c, Manifest.permission.ACCESS_BACKGROUND_LOCATION)),
            "activity" to (Build.VERSION.SDK_INT < 29 || g(c, Manifest.permission.ACTIVITY_RECOGNITION)),
            "calendar" to g(c, Manifest.permission.READ_CALENDAR),
            "usage" to usage(c),
            "overlay" to (Build.VERSION.SDK_INT < 23 || Settings.canDrawOverlays(c)),
            "dnd" to (Build.VERSION.SDK_INT < 23 || nm.isNotificationPolicyAccessGranted),
            "listener" to NotificationManagerCompat.getEnabledListenerPackages(c).contains(c.packageName),
            "accessibility" to acc.contains(c.packageName + "/"),
            "mic" to g(c, Manifest.permission.RECORD_AUDIO),
            "battery" to (Build.VERSION.SDK_INT < 23 || pm.isIgnoringBatteryOptimizations(c.packageName)),
        )
    }

    fun request(a: Activity, key: String) {
        val pkg = Uri.parse("package:" + a.packageName)
        fun runtime(vararg p: String) = ActivityCompat.requestPermissions(a, arrayOf(*p), 7)
        fun open(i: Intent) = try { a.startActivity(i) } catch (_: Exception) { a.startActivity(Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, pkg)) }
        when (key) {
            "notifications" -> if (Build.VERSION.SDK_INT >= 33) runtime(Manifest.permission.POST_NOTIFICATIONS)
                else open(Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, pkg))
            "location" -> runtime(Manifest.permission.ACCESS_FINE_LOCATION, Manifest.permission.ACCESS_COARSE_LOCATION)
            "backgroundLocation" -> if (Build.VERSION.SDK_INT >= 30) open(Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, pkg))
                else if (Build.VERSION.SDK_INT == 29) runtime(Manifest.permission.ACCESS_BACKGROUND_LOCATION)
            "activity" -> if (Build.VERSION.SDK_INT >= 29) runtime(Manifest.permission.ACTIVITY_RECOGNITION)
            "calendar" -> runtime(Manifest.permission.READ_CALENDAR)
            "mic" -> runtime(Manifest.permission.RECORD_AUDIO)
            "usage" -> open(Intent(Settings.ACTION_USAGE_ACCESS_SETTINGS))
            "overlay" -> if (Build.VERSION.SDK_INT >= 23) open(Intent(Settings.ACTION_MANAGE_OVERLAY_PERMISSION, pkg))
            "dnd" -> open(Intent(Settings.ACTION_NOTIFICATION_POLICY_ACCESS_SETTINGS))
            "listener" -> open(Intent(Settings.ACTION_NOTIFICATION_LISTENER_SETTINGS))
            "accessibility" -> open(Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS))
            "battery" -> if (Build.VERSION.SDK_INT >= 23) {
                @Suppress("BatteryLife")
                open(Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS, pkg))
            }
        }
    }
}
