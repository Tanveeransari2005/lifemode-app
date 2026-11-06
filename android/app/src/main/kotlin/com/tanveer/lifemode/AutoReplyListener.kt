package com.tanveer.lifemode

import android.app.Notification
import android.app.RemoteInput
import android.content.Intent
import android.os.Bundle
import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification

/** Driving auto-reply for WhatsApp / Instagram using the notification's own
 *  Reply action (RemoteInput). Only 1:1 chats, once per chat per 15 min, and
 *  only while Driving mode is active. Message text is never stored. */
class AutoReplyListener : NotificationListenerService() {
    companion object {
        val apps = setOf("com.whatsapp", "com.whatsapp.w4b", "com.instagram.android")
        private val lastReply = HashMap<String, Long>()
    }

    override fun onNotificationPosted(sbn: StatusBarNotification) {
        if (!Live.autoReplyActive || sbn.packageName !in apps) return
        val n = sbn.notification ?: return
        if (n.flags and Notification.FLAG_GROUP_SUMMARY != 0) return
        val ex = n.extras ?: return
        if (ex.getBoolean(Notification.EXTRA_IS_GROUP_CONVERSATION, false)) return
        val title = ex.getCharSequence(Notification.EXTRA_TITLE)?.toString() ?: return
        if (title.contains(":") || title.contains("WhatsApp", true) && title.length < 12) return // "Group: Person", system notes
        val key = sbn.packageName + "|" + (n.shortcutId ?: title)
        val now = System.currentTimeMillis()
        if (now - (lastReply[key] ?: 0L) < 15 * 60_000L) return

        val action = findReply(n) ?: return
        val ri = action.remoteInputs?.firstOrNull { it.allowFreeFormInput } ?: return
        val text = Live.autoReplyText.ifBlank { "Main drive kar rahi hoon, baad me baat karti hoon." }
        val intent = Intent()
        val bundle = Bundle().apply { putCharSequence(ri.resultKey, text) }
        RemoteInput.addResultsToIntent(arrayOf(ri), intent, bundle)
        try {
            action.actionIntent.send(this, 0, intent)
            lastReply[key] = now
        } catch (_: Exception) {}
    }

    private fun findReply(n: Notification): Notification.Action? {
        n.actions?.firstOrNull { a -> a.remoteInputs?.any { it.allowFreeFormInput } == true }?.let { return it }
        return Notification.WearableExtender(n).actions.firstOrNull { a -> a.remoteInputs?.any { it.allowFreeFormInput } == true }
    }
}
