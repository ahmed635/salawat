package com.salawat.app

import android.animation.ValueAnimator
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
import android.view.animation.DecelerateInterpolator
import android.widget.TextView
import android.widget.Toast

/**
 * The floating salawat bubble — a draggable circle showing the running count
 * that increments on tap, Messenger chat-head style.
 *
 * Drawn natively rather than through a second Flutter engine. The bubble is a
 * circle with a number; spinning up an engine for that would cost tens of MB
 * and hundreds of milliseconds on a low-end device, and would drag the
 * cross-isolate SharedPreferences hazard back in. Taps go straight to
 * [TapReceiver.applyTap], the same path the widget uses, so the Flutter app
 * still reconciles them on resume exactly as before.
 *
 * Two costs the user accepts by turning this on, both unavoidable on Android:
 *  * SYSTEM_ALERT_WINDOW, granted from a system settings screen. Asked for
 *    exactly once, by the first-run flow in `core/quick_tap_setup.dart`.
 *  * A foreground service, which *must* post a notification. The bubble can't
 *    stay alive without one — see [QuickTapNotification].
 *
 * Getting rid of it is a dismissal, not a teardown: dragging the bubble onto
 * the X (or long-pressing it) hides it until the app is next opened, and it
 * comes back on its own the next time the user leaves the app. Nothing is
 * re-asked, because the permission was never given back. The permanent off
 * switch is the profile toggle. See [SalawatBuffer.dismissed].
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

    /** The X target, added only while a drag is in progress. */
    private var dismissView: View? = null
    private var dismissCircle: View? = null

    /** Screen coordinates of the X's centre; null until it has been laid out. */
    private var dismissCenter: FloatArray? = null
    private val scratch = IntArray(2)

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

        /**
         * Every gate lives here rather than at the call sites — the bubble is
         * started from four places (app backgrounding, boot, app update, the
         * profile toggle) and each one forgetting a condition is a bubble that
         * shows up when the user asked it not to.
         */
        fun start(context: Context) {
            if (!SalawatBuffer.quickTapEnabled(context)) return
            if (SalawatBuffer.dismissed(context)) return
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

        val lp = WindowManager.LayoutParams(
            WindowManager.LayoutParams.WRAP_CONTENT,
            WindowManager.LayoutParams.WRAP_CONTENT,
            overlayWindowType(),
            // NOT_FOCUSABLE so the bubble never steals input from whatever the
            // user is actually doing — it must not swallow keystrokes or close
            // the keyboard in another app.
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE,
            PixelFormat.TRANSLUCENT,
        ).apply {
            gravity = Gravity.TOP or Gravity.START
            // Where the user last left it. The x default is provisional — the
            // first layout parks it against an edge, which needs the measured
            // width.
            val saved = SalawatBuffer.position(this@OverlayService)
            x = saved?.first ?: 0
            y = saved?.second ?: 320
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

        // A saved position can be off-screen by the time it's used: a rotation,
        // a foldable opening, or a different display since the drop. Clamping
        // needs the measured size, so it waits for the first layout pass.
        view.post {
            if (SalawatBuffer.position(this) == null) placeAtDefaultEdge()
            clampIntoScreen()
        }

        windowManager = wm
        bubble = view
        countLabel = label
        params = lp
        instance = this
    }

    /**
     * First appearance only: parks the bubble against the right edge, the side
     * a right-handed thumb reaches in an RTL app. Left mid-screen it would sit
     * on top of whatever the user opened next — and every later release snaps
     * to an edge anyway, so starting at one keeps the resting places uniform.
     */
    private fun placeAtDefaultEdge() {
        val view = bubble ?: return
        val lp = params ?: return
        lp.x = (resources.displayMetrics.widthPixels - view.width)
            .coerceAtLeast(0)
        SalawatBuffer.setPosition(this, lp.x, lp.y)
        try {
            windowManager?.updateViewLayout(view, lp)
        } catch (e: Exception) {
            // View already detached.
        }
    }

    /**
     * Pulls the bubble back inside the screen and re-saves it. Runs on the
     * first layout and on every configuration change, so a position saved in
     * portrait can't strand the bubble off the edge in landscape.
     */
    private fun clampIntoScreen() {
        val view = bubble ?: return
        val lp = params ?: return
        val wm = windowManager ?: return
        val dm = resources.displayMetrics
        val x = lp.x.coerceIn(0, (dm.widthPixels - view.width).coerceAtLeast(0))
        val y = lp.y.coerceIn(0, (dm.heightPixels - view.height).coerceAtLeast(0))
        if (x == lp.x && y == lp.y) return
        lp.x = x
        lp.y = y
        try {
            wm.updateViewLayout(view, lp)
        } catch (e: Exception) {
            return
        }
        SalawatBuffer.setPosition(this, x, y)
    }

    override fun onConfigurationChanged(newConfig: android.content.res.Configuration) {
        super.onConfigurationChanged(newConfig)
        bubble?.post { clampIntoScreen() }
    }

    private fun overlayWindowType(): Int =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
        } else {
            @Suppress("DEPRECATION")
            WindowManager.LayoutParams.TYPE_PHONE
        }

    // --- The X target ---------------------------------------------------

    /**
     * Added on drag start and removed on drop, so nothing sits at the bottom
     * of the user's screen the rest of the time.
     *
     * FLAG_NOT_TOUCHABLE: the target never receives events of its own. The
     * bubble already holds the touch stream for the whole gesture, and a
     * second window competing for it would break the drag the moment the
     * finger crossed the boundary. Whether the bubble is "over" the X is
     * decided by distance in [BubbleTouchListener], not by hit-testing.
     */
    private fun showDismissTarget() {
        if (dismissView != null) return
        val wm = windowManager ?: return
        val view = LayoutInflater.from(this)
            .inflate(R.layout.overlay_dismiss_target, null)

        val lp = WindowManager.LayoutParams(
            WindowManager.LayoutParams.MATCH_PARENT,
            WindowManager.LayoutParams.WRAP_CONTENT,
            overlayWindowType(),
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
                    WindowManager.LayoutParams.FLAG_NOT_TOUCHABLE or
                    WindowManager.LayoutParams.FLAG_LAYOUT_NO_LIMITS,
            PixelFormat.TRANSLUCENT,
        ).apply {
            gravity = Gravity.BOTTOM or Gravity.CENTER_HORIZONTAL
        }

        try {
            wm.addView(view, lp)
        } catch (e: Exception) {
            return
        }
        view.alpha = 0f
        view.animate().alpha(1f).setDuration(140).start()
        dismissView = view
        dismissCircle = view.findViewById<View>(R.id.overlay_dismiss_circle).also { circle ->
            // Measured rather than derived from display metrics: the bubble's
            // window and this one are inset differently by the status and
            // navigation bars, and a magnet that is off by a nav-bar height is
            // worse than no magnet at all.
            circle.post {
                circle.getLocationOnScreen(scratch)
                dismissCenter = floatArrayOf(
                    scratch[0] + circle.width / 2f,
                    scratch[1] + circle.height / 2f,
                )
            }
        }
    }

    private fun hideDismissTarget() {
        val view = dismissView ?: return
        dismissView = null
        dismissCircle = null
        dismissCenter = null
        try {
            windowManager?.removeView(view)
        } catch (e: Exception) {
            // Already detached.
        }
    }

    private fun dismissForNow() {
        SalawatBuffer.setDismissed(this, true)
        Toast.makeText(
            this,
            "تم إخفاء العدّاد — سيعود عند فتح التطبيق",
            Toast.LENGTH_SHORT,
        ).show()
        stopSelf()
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
        private var overTarget = false

        private val slop = (8 * resources.displayMetrics.density)
        private val captureRadius = CAPTURE_RADIUS_DP * resources.displayMetrics.density
        private val handler = android.os.Handler(android.os.Looper.getMainLooper())

        /** Long-press is the shortcut for the same dismissal the X performs —
         *  a one-handed way out for users who never discover the drag. */
        private val longPress = Runnable {
            longPressFired = true
            dismissForNow()
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
                    overTarget = false
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
                        showDismissTarget()
                    }
                    if (dragging) {
                        lp.x = initialX + dx.toInt()
                        lp.y = initialY + dy.toInt()
                        updateMagnet()
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
                    // A cancelled gesture is the system taking the touch away,
                    // not the user letting go over the X. Dismissing on it
                    // would make the bubble vanish out of nowhere.
                    val dropped = overTarget && event.action == MotionEvent.ACTION_UP
                    hideDismissTarget()
                    if (dropped) {
                        dismissForNow()
                    } else if (dragging) {
                        // Undo the shrink the magnet applied, if any.
                        view.animate().scaleX(1f).scaleY(1f).setDuration(120).start()
                        snapToEdge()
                    } else if (!longPressFired) {
                        val count = TapReceiver.applyTap(this@OverlayService)
                        countLabel?.text = SalawatBuffer.formatArabic(count)
                        v.performClick()
                    }
                    return true
                }
            }
            return false
        }

        /**
         * Pulls the bubble the last few dp onto the X once it is close, the
         * way Messenger does. Without it the user has to land a 64dp circle on
         * a 64dp circle by eye, one-handed, while it sits under their thumb.
         */
        private fun updateMagnet() {
            val target = dismissCenter ?: return
            // Screen coordinates on both sides. The position lags the drag by
            // a frame, which is nothing against a 90dp capture radius.
            view.getLocationOnScreen(scratch)
            val dx = scratch[0] + view.width / 2f - target[0]
            val dy = scratch[1] + view.height / 2f - target[1]
            val near = kotlin.math.hypot(dx, dy) < captureRadius

            if (near == overTarget) return
            overTarget = near
            dismissCircle?.animate()
                ?.scaleX(if (near) 1.3f else 1f)
                ?.scaleY(if (near) 1.3f else 1f)
                ?.setDuration(120)
                ?.start()
            view.animate()
                .scaleX(if (near) 0.8f else 1f)
                .scaleY(if (near) 0.8f else 1f)
                .setDuration(120)
                .start()
        }

        /**
         * Parks the bubble against the nearest side edge on release, and keeps
         * it inside the screen vertically. A bubble abandoned mid-screen sits
         * on top of whatever the user is reading, which is the fastest way to
         * make them want it gone for good.
         */
        private fun snapToEdge() {
            val dm = resources.displayMetrics
            val maxX = dm.widthPixels - view.width
            val targetX = if (lp.x + view.width / 2 < dm.widthPixels / 2) 0 else maxX
            val clampedY = lp.y.coerceIn(0, (dm.heightPixels - view.height).coerceAtLeast(0))

            // Saved up front rather than when the animation ends: the resting
            // place is already known, and the service can be stopped mid-flight
            // (the app coming back to the foreground does exactly that).
            SalawatBuffer.setPosition(this@OverlayService, targetX, clampedY)

            val fromX = lp.x
            val fromY = lp.y
            ValueAnimator.ofFloat(0f, 1f).apply {
                duration = 220
                interpolator = DecelerateInterpolator()
                addUpdateListener { anim ->
                    val t = anim.animatedValue as Float
                    lp.x = (fromX + (targetX - fromX) * t).toInt()
                    lp.y = (fromY + (clampedY - fromY) * t).toInt()
                    try {
                        wm.updateViewLayout(view, lp)
                    } catch (e: Exception) {
                        cancel()
                    }
                }
                start()
            }
        }
    }

    override fun onDestroy() {
        instance = null
        hideDismissTarget()
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
        // Stopping the service takes its notification with it, which is the
        // whole point — the row exists only to keep this service alive.
        super.onDestroy()
    }
}

/** Generous on purpose: the bubble is under the user's thumb and invisible. */
private const val CAPTURE_RADIUS_DP = 90f
