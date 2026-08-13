package com.salawat.app

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat

/**
 * The ongoing "quick tap" notification: a persistent row in the shade with a
 * صلِّ action button, so the user can add salawat without opening the app.
 *
 * Deliberately *not* a foreground service. A service would let the count sit
 * in a floating overlay too, but it's the thing OEM battery managers
 * force-stop — the same mechanism that killed the old AlarmManager reminders
 * and pushed them to FCM (see `core/notifications.dart`). A plain ongoing
 * notification survives that, costs no permission beyond POST_NOTIFICATIONS,
 * and needs no Play `specialUse` justification.
 *
 * Its own channel, at IMPORTANCE_LOW: this must never make a sound or peek.
 * The reminders channel in `notifications.dart` is high-importance and is
 * left alone.
 */
object QuickTapNotification {
    const val CHANNEL_ID = "salawat_quick_tap"
    const val NOTIFICATION_ID = 4711

    private const val CHANNEL_NAME = "التسبيح السريع"
    private const val CHANNEL_DESC = "إشعار ثابت لإضافة الصلوات دون فتح التطبيق"

    fun ensureChannel(context: Context) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val channel = NotificationChannel(
            CHANNEL_ID,
            CHANNEL_NAME,
            NotificationManager.IMPORTANCE_LOW,
        ).apply {
            description = CHANNEL_DESC
            setShowBadge(false)
            enableVibration(false)
            setSound(null, null)
        }
        val nm = context.getSystemService(Context.NOTIFICATION_SERVICE)
                as NotificationManager
        nm.createNotificationChannel(channel)
    }

    fun show(context: Context, count: Int) {
        ensureChannel(context)
        try {
            NotificationManagerCompat.from(context)
                .notify(NOTIFICATION_ID, buildOngoing(context, count))
        } catch (e: SecurityException) {
            // POST_NOTIFICATIONS denied on Android 13+. Nothing to do — the
            // in-app counter is unaffected.
        }
    }

    /**
     * The notification object itself. Split out because [OverlayService] must
     * hand one to `startForeground` rather than post it — a foreground service
     * is required to keep the floating bubble alive, and Android requires a
     * notification to accompany it.
     */
    fun buildOngoing(context: Context, count: Int): android.app.Notification {
        val tapIntent = Intent(context, TapReceiver::class.java).apply {
            action = TapReceiver.ACTION_TAP
            putExtra(TapReceiver.EXTRA_SOURCE, "notification")
        }
        val tapPending = PendingIntent.getBroadcast(
            context,
            0,
            tapIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )

        // Swiping the notification away is the most natural "make this stop"
        // gesture, and on Android 14+ even an ongoing notification can be
        // dismissed. Without this the next tap simply re-posted it, so it
        // looked like the notification refused to die.
        val stopIntent = Intent(context, TapReceiver::class.java).apply {
            action = TapReceiver.ACTION_STOP
        }
        val stopPending = PendingIntent.getBroadcast(
            context,
            2,
            stopIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )

        val openIntent = context.packageManager
            .getLaunchIntentForPackage(context.packageName)
            ?.apply { flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP }
        val openPending = PendingIntent.getActivity(
            context,
            1,
            openIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )

        return NotificationCompat.Builder(context, CHANNEL_ID)
            .setSmallIcon(R.drawable.notification_icon)
            .setContentTitle("صلوا عليه")
            .setContentText("صلاة اليوم: ${SalawatBuffer.formatArabic(count)}")
            .setContentIntent(openPending)
            .addAction(0, "صلِّ عليه ﷺ", tapPending)
            // An explicit off switch, so stopping doesn't depend on the user
            // guessing that a swipe is what disables it.
            .addAction(0, "إيقاف", stopPending)
            .setDeleteIntent(stopPending)
            .setOngoing(true)
            .setSilent(true)
            .setShowWhen(false)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            .build()
    }

    fun hide(context: Context) {
        NotificationManagerCompat.from(context).cancel(NOTIFICATION_ID)
    }

    /** Re-post only if the user had it switched on. */
    fun refreshIfEnabled(context: Context) {
        if (SalawatBuffer.quickTapEnabled(context)) {
            show(context, SalawatBuffer.display(context))
        }
    }
}
