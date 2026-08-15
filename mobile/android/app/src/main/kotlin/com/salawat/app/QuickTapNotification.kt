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
 * The notification that accompanies [OverlayService].
 *
 * Not a surface in its own right. Android will not let a foreground service —
 * the only way to keep the floating bubble on screen — run without a
 * notification, so this is the price of the bubble rather than a feature.
 * It carries no action buttons: the bubble *is* the button, and duplicating
 * it in the shade only gave the user two things to find and turn off.
 * Tapping the row opens the app; that's all it does.
 *
 * Its own channel, at IMPORTANCE_LOW: this must never make a sound or peek.
 * The reminders channel in `notifications.dart` is high-importance and is
 * left alone.
 */
object QuickTapNotification {
    const val CHANNEL_ID = "salawat_quick_tap"
    const val NOTIFICATION_ID = 4711

    private const val CHANNEL_NAME = "العدّاد العائم"
    private const val CHANNEL_DESC = "مطلوب لإبقاء العدّاد العائم على الشاشة"

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

    /**
     * The notification object itself, handed to `startForeground` rather than
     * posted — posting it independently would leave a row in the shade with no
     * service behind it.
     */
    fun buildOngoing(context: Context, count: Int): android.app.Notification {
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
            .setOngoing(true)
            .setSilent(true)
            .setShowWhen(false)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            .build()
    }

    /**
     * Re-renders the count. Only while the service is alive — re-posting this
     * ID without one would strand an undismissable row in the shade.
     */
    fun refresh(context: Context, count: Int) {
        if (!OverlayService.isRunning()) return
        try {
            NotificationManagerCompat.from(context)
                .notify(NOTIFICATION_ID, buildOngoing(context, count))
        } catch (e: SecurityException) {
            // POST_NOTIFICATIONS denied on Android 13+. The service still runs
            // and the bubble is unaffected; only this row is missing.
        }
    }

    fun hide(context: Context) {
        NotificationManagerCompat.from(context).cancel(NOTIFICATION_ID)
    }
}
