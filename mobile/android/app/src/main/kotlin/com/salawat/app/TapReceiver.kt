package com.salawat.app

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager

/**
 * Handles a tap from the ongoing notification's action button or the
 * home-screen widget.
 *
 * Runs entirely in Kotlin — no Flutter engine is spawned. That's the point:
 * booting an engine per tap would cost hundreds of milliseconds, burn memory
 * on low-end devices, and drag the cross-isolate SharedPreferences hazard
 * back in. All this does is append to [SalawatBuffer] and re-render the two
 * surfaces; the Flutter app reconciles on its next resume.
 */
class TapReceiver : BroadcastReceiver() {
    companion object {
        const val ACTION_TAP = "com.salawat.app.ACTION_TAP"
        const val EXTRA_SOURCE = "source"

        /**
         * Turns every background surface off for good.
         *
         * Reachable without opening the app — from the notification's "إيقاف"
         * button, from swiping the notification away, and from a long-press on
         * the bubble. That matters because the service is START_STICKY and
         * survives the app being swiped out of recents: without an off switch
         * that lives *outside* the app, a user who wanted the bubble gone had
         * no way to remove it.
         */
        const val ACTION_STOP = "com.salawat.app.ACTION_STOP"

        fun stopAll(context: Context) {
            SalawatBuffer.setQuickTapEnabled(context, false)
            OverlayService.stop(context)
            QuickTapNotification.hide(context)
        }

        /**
         * The one place a background tap is recorded, shared by the
         * notification action, the widget, and the floating bubble. Returns
         * the new display count so a caller with its own UI can render it
         * without a second read.
         */
        fun applyTap(context: Context): Int {
            val display = SalawatBuffer.append(context, 1)
            // Same 20ms light tap the in-app counter uses (core/haptics.dart),
            // so every surface feels identical.
            vibrate(context)
            if (SalawatBuffer.quickTapEnabled(context)) {
                QuickTapNotification.show(context, display)
            }
            SalawatWidgetProvider.renderAll(context)
            OverlayService.render(display)
            return display
        }

        private fun vibrate(context: Context) {
            try {
                val vibrator = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                    val manager = context.getSystemService(Context.VIBRATOR_MANAGER_SERVICE)
                            as VibratorManager
                    manager.defaultVibrator
                } else {
                    @Suppress("DEPRECATION")
                    context.getSystemService(Context.VIBRATOR_SERVICE) as Vibrator
                }
                if (!vibrator.hasVibrator()) return
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    vibrator.vibrate(
                        VibrationEffect.createOneShot(20, VibrationEffect.DEFAULT_AMPLITUDE)
                    )
                } else {
                    @Suppress("DEPRECATION")
                    vibrator.vibrate(20)
                }
            } catch (e: Exception) {
                // Haptics are a nicety; never let them break the tap.
            }
        }
    }

    override fun onReceive(context: Context, intent: Intent) {
        when (intent.action) {
            ACTION_TAP -> applyTap(context)

            ACTION_STOP -> stopAll(context)

            Intent.ACTION_BOOT_COMPLETED,
            Intent.ACTION_MY_PACKAGE_REPLACED -> {
                // Notifications don't survive a reboot or an app update, so the
                // quick-tap row would silently vanish and never come back until
                // the user next opened the app.
                QuickTapNotification.refreshIfEnabled(context)
                SalawatWidgetProvider.renderAll(context)
                OverlayService.restoreIfEnabled(context)
            }
        }
    }
}
