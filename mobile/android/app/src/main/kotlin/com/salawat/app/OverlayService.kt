package com.salawat.app

import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.graphics.PixelFormat
import android.os.Build
import android.os.IBinder
import android.provider.Settings
import android.view.Gravity
import android.view.LayoutInflater
import android.view.MotionEvent
import android.view.View
import android.view.WindowManager
import android.widget.TextView

/**
 * The floating salawat bubble — a draggable circle showing the running count
 * that increments on tap, Messenger chat-head style.
 *
 * Drawn natively rather than through a second Flutter engine. The bubble is a
 * circle with a number; spinning up an engine for that would cost tens of MB
 * and hundreds of milliseconds on a low-end device, and would drag the
 * cross-isolate SharedPreferences hazard back in. Taps go straight to
 * [TapReceiver.applyTap], the same path the notification and widget use, so
 * the Flutter app still reconciles them on resume exactly as before.
 *
 * Two costs the user accepts by turning this on, both unavoidable on Android:
 *  * SYSTEM_ALERT_WINDOW, granted from a system settings screen.
 *  * A foreground service, which *must* post a notification. The bubble can't
 *    stay alive without one.
 *
 * Aggressive OEM battery managers (Realme/Xiaomi/Huawei — the same ones that
 * killed the old AlarmManager reminders, see `core/notifications.dart`) can
 * still force-stop this. [TapReceiver] re-starts it on boot and app update,
 * which covers the common cases but not a mid-session kill.
 */
class OverlayService : Service() {

    private var windowManager: WindowManager? = null
    private var bubble: View? = null
    private var countLabel: TextView? = null
    private var params: WindowManager.LayoutParams? = null

    companion object {
        const val ACTION_START = "com.salawat.app.OVERLAY_START"
        const val ACTION_STOP = "com.salawat.app.OVERLAY_STOP"

        /** Live instance, so a tap from any surface can refresh the label. */
        private var instance: OverlayService? = null

        fun isRunning(): Boolean = instance != null

        fun render(count: Int) {
            instance?.let { service ->
                service.countLabel?.post {
                    service.countLabel?.text = SalawatBuffer.formatArabic(count)
                }
            }
        }

        fun canDrawOverlays(context: Context): Boolean =
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                Settings.canDrawOverlays(context)
            } else {
                true
            }

        fun start(context: Context) {
            if (!canDrawOverlays(context)) return
            val intent = Intent(context, OverlayService::class.java).apply {
                action = ACTION_START
            }
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(intent)
            } else {
                context.startService(intent)
            }
        }

        fun stop(context: Context) {
            context.stopService(Intent(context, OverlayService::class.java))
        }

        /** Used after boot / app update, where the service is gone but the
         *  user's preference isn't. */
        fun restoreIfEnabled(context: Context) {
            if (SalawatBuffer.quickTapEnabled(context) && canDrawOverlays(context)) {
                start(context)
            }
        }
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == ACTION_STOP) {
            stopSelf()
            return START_NOT_STICKY
        }
        startInForeground()
        showBubble()
        // START_STICKY so the system brings the bubble back if it reclaims the
        // process under memory pressure.
        return START_STICKY
    }

    private fun startInForeground() {
        QuickTapNotification.ensureChannel(this)
        val notification = QuickTapNotification.buildOngoing(
            this,
            SalawatBuffer.display(this),
        )
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            startForeground(
                QuickTapNotification.NOTIFICATION_ID,
                notification,
                ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE,
            )
        } else {
            startForeground(QuickTapNotification.NOTIFICATION_ID, notification)
        }
    }

    private fun showBubble() {
        if (bubble != null) return
        if (!canDrawOverlays(this)) {
            stopSelf()
            return
        }

        val wm = getSystemService(Context.WINDOW_SERVICE) as WindowManager
        val view = LayoutInflater.from(this).inflate(R.layout.overlay_bubble, null)
        val label = view.findViewById<TextView>(R.id.overlay_count)
        label.text = SalawatBuffer.formatArabic(SalawatBuffer.display(this))

        val type = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
        } else {
            @Suppress("DEPRECATION")
            WindowManager.LayoutParams.TYPE_PHONE
        }

        val lp = WindowManager.LayoutParams(
            WindowManager.LayoutParams.WRAP_CONTENT,
            WindowManager.LayoutParams.WRAP_CONTENT,
            type,
            // NOT_FOCUSABLE so the bubble never steals input from whatever the
            // user is actually doing — it must not swallow keystrokes or close
            // the keyboard in another app.
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE,
            PixelFormat.TRANSLUCENT,
        ).apply {
            gravity = Gravity.TOP or Gravity.START
            x = 24
            y = 320
        }

        view.setOnTouchListener(BubbleTouchListener(wm, lp, view))

        try {
            wm.addView(view, lp)
        } catch (e: Exception) {
            // Permission revoked between the check and here, or an OEM refusing
            // the window type. Nothing to show — shut down cleanly.
            stopSelf()
            return
        }

        windowManager = wm
        bubble = view
        countLabel = label
        params = lp
        instance = this
    }

    /**
     * Distinguishes a tap from a drag. Without the slop threshold every drag
     * would also register a salawat, which would be worse than a missed tap —
     * the count is the whole point and must not inflate by accident.
     */
    private inner class BubbleTouchListener(
        private val wm: WindowManager,
        private val lp: WindowManager.LayoutParams,
        private val view: View,
    ) : View.OnTouchListener {

        private var initialX = 0
        private var initialY = 0
        private var touchX = 0f
        private var touchY = 0f
        private var dragging = false
        private var longPressFired = false

        private val slop = (8 * resources.displayMetrics.density)
        private val handler = android.os.Handler(android.os.Looper.getMainLooper())

        /** Long-press turns the feature off — a way out that doesn't require
         *  finding the notification or opening the app. One flag now, so this
         *  clears the notification too rather than leaving half of it behind. */
        private val longPress = Runnable {
            longPressFired = true
            android.widget.Toast.makeText(
                this@OverlayService,
                "تم إيقاف التسبيح السريع",
                android.widget.Toast.LENGTH_SHORT,
            ).show()
            TapReceiver.stopAll(this@OverlayService)
        }

        override fun onTouch(v: View, event: MotionEvent): Boolean {
            when (event.action) {
                MotionEvent.ACTION_DOWN -> {
                    initialX = lp.x
                    initialY = lp.y
                    touchX = event.rawX
                    touchY = event.rawY
                    dragging = false
                    longPressFired = false
                    handler.postDelayed(longPress, 600)
                    return true
                }
                MotionEvent.ACTION_MOVE -> {
                    val dx = event.rawX - touchX
                    val dy = event.rawY - touchY
                    if (!dragging && (kotlin.math.abs(dx) > slop ||
                                kotlin.math.abs(dy) > slop)
                    ) {
                        dragging = true
                        // Moving means they're repositioning, not dismissing.
                        handler.removeCallbacks(longPress)
                    }
                    if (dragging) {
                        lp.x = initialX + dx.toInt()
                        lp.y = initialY + dy.toInt()
                        try {
                            wm.updateViewLayout(view, lp)
                        } catch (e: Exception) {
                            // View already detached; ignore.
                        }
                    }
                    return true
                }
                MotionEvent.ACTION_UP, MotionEvent.ACTION_CANCEL -> {
                    handler.removeCallbacks(longPress)
                    if (!dragging && !longPressFired) {
                        val count = TapReceiver.applyTap(this@OverlayService)
                        countLabel?.text = SalawatBuffer.formatArabic(count)
                        v.performClick()
                    }
                    return true
                }
            }
            return false
        }
    }

    override fun onDestroy() {
        instance = null
        bubble?.let { view ->
            try {
                windowManager?.removeView(view)
            } catch (e: Exception) {
                // Already removed.
            }
        }
        bubble = null
        countLabel = null
        windowManager = null

        // Stopping the service takes its foreground notification with it. If
        // the user still wants the standalone quick-tap row, put it back —
        // otherwise dismissing the bubble would silently disable the
        // notification too. When the user chose "stop everything", the flag is
        // already false and this is a no-op.
        if (SalawatBuffer.quickTapEnabled(this)) {
            QuickTapNotification.show(this, SalawatBuffer.display(this))
        }
        super.onDestroy()
    }
}
