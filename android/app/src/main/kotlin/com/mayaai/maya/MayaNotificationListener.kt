package com.mayaai.maya

import android.app.Notification
import android.app.RemoteInput
import android.content.Intent
import android.os.Bundle
import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification

/**
 * Collects recent chat messages from notifications (WhatsApp, SMS, Telegram…)
 * so Maya can read them aloud and reply by voice. Nothing leaves the phone.
 */
class MayaNotificationListener : NotificationListenerService() {

    data class Msg(
        val id: Long,
        val pkg: String,
        val app: String,
        val sender: String,
        val text: String,
        val time: Long,
        val reply: Notification.Action?,
    )

    companion object {
        @Volatile var instance: MayaNotificationListener? = null
        private val messages = ArrayDeque<Msg>()
        private var nextId = 1L

        private val apps = mapOf(
            "com.whatsapp" to "WhatsApp",
            "com.whatsapp.w4b" to "WhatsApp Business",
            "com.google.android.apps.messaging" to "Messages",
            "com.android.mms" to "Messages",
            "com.samsung.android.messaging" to "Messages",
            "com.android.messaging" to "Messages",
            "org.telegram.messenger" to "Telegram",
            "com.facebook.orca" to "Messenger",
            "com.instagram.android" to "Instagram",
        )

        fun recent(): List<Map<String, Any>> = synchronized(messages) {
            messages.map {
                mapOf(
                    "id" to it.id,
                    "app" to it.app,
                    "sender" to it.sender,
                    "text" to it.text,
                    "time" to it.time,
                    "canReply" to (it.reply != null),
                )
            }
        }

        fun find(id: Long): Msg? = synchronized(messages) { messages.firstOrNull { it.id == id } }

        fun clear() = synchronized(messages) { messages.clear() }
    }

    override fun onListenerConnected() {
        instance = this
    }

    override fun onListenerDisconnected() {
        instance = null
    }

    override fun onNotificationPosted(sbn: StatusBarNotification) {
        val app = apps[sbn.packageName] ?: return
        val n = sbn.notification ?: return
        if (n.flags and Notification.FLAG_GROUP_SUMMARY != 0) return
        val extras = n.extras ?: return

        var sender = extras.getCharSequence(Notification.EXTRA_TITLE)?.toString() ?: return
        var text = extras.getCharSequence(Notification.EXTRA_TEXT)?.toString() ?: ""

        // Chat apps put the real messages in EXTRA_MESSAGES; use the newest one.
        @Suppress("DEPRECATION")
        val list = extras.getParcelableArray(Notification.EXTRA_MESSAGES)
        val last = list?.lastOrNull() as? Bundle
        if (last != null) {
            last.getCharSequence("text")?.toString()?.let { text = it }
            val from = last.getCharSequence("sender")?.toString()
            val group = extras.getCharSequence(Notification.EXTRA_CONVERSATION_TITLE)?.toString()
            if (from != null) {
                sender = if (group != null && group != from) "$from ($group)" else from
            }
        }
        if (text.isBlank()) return
        // Skip summaries like "5 new messages" or "Checking for new messages".
        val lower = text.lowercase()
        if (Regex("^\\d+ new messages?").containsMatchIn(lower) || lower.contains("checking for new messages")) return

        val reply = n.actions?.firstOrNull { a -> a.remoteInputs?.isNotEmpty() == true }
        synchronized(messages) {
            if (messages.any { it.pkg == sbn.packageName && it.sender == sender && it.text == text }) return
            messages.addLast(Msg(nextId++, sbn.packageName, app, sender, text, System.currentTimeMillis(), reply))
            while (messages.size > 60) messages.removeFirst()
        }
    }

    /** Sends [text] through the notification's own reply box. */
    fun reply(msg: Msg, text: String): Boolean {
        val action = msg.reply ?: return false
        val inputs = action.remoteInputs ?: return false
        return try {
            val intent = Intent()
            val results = Bundle()
            for (input in inputs) results.putCharSequence(input.resultKey, text)
            RemoteInput.addResultsToIntent(inputs, intent, results)
            action.actionIntent.send(this, 0, intent)
            true
        } catch (e: Exception) {
            false
        }
    }
}
