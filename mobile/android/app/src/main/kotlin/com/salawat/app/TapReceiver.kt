package com.salawat.app

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager

/**
 * Handles a tap from the home-screen widget, and brings the floating bubble
 * back after a reboot or an app update.
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
         * The one place a background tap is recorded, shared by the
         * home-screen widget and the floating bubble. Returns the new display
         * count so a caller with its own UI can render it without a second
         * read.
         */
        fun applyTap(context: Context): Int {
            val display = SalawatBuffer.append(context, 1)
            // Same 20ms light tap the in-app counter uses (core/haptics.dart),
            // so every surface feels identical.
            vibrate(context)
            QuickTapNotification.refresh(context, display)
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

            Intent.ACTION_BOOT_COMPLETED,
            Intent.ACTION_MY_PACKAGE_REPLACED -> {
                // The service doesn't survive a reboot or an app update, so the
                // bubble would silently vanish and never come back until the
                // user next opened the app. `start` re-checks the user's
                // preference, the permission, and any pending dismissal.
                SalawatWidgetProvider.renderAll(context)
                OverlayService.start(context)
            }
        }
    }
}
