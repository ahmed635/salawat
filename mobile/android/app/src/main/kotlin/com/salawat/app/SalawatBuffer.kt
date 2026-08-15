package com.salawat.app

import android.content.Context
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

/**
 * Append-only buffer for taps made outside the Flutter app (ongoing
 * notification, home-screen widget).
 *
 * Why this exists at all: every "act while backgrounded" surface on Android
 * runs its Dart callback in a *separate* Flutter engine and isolate, and
 * SharedPreferences caches values in memory per-isolate. Two isolates doing
 * read-modify-write on the counter lose taps, and — far worse — racing on
 * `lastSyncedCount` / `pendingReqId` can leave localCount < lastSyncedCount,
 * which stalls CounterSync permanently (the same hazard CounterSync's own
 * doc comment calls out for the daily reset).
 *
 * So background surfaces never touch the real counter and never sync. They
 * only append here, in one process-wide synchronized place, and the Flutter
 * app drains this into CounterController on resume. Single writer for sync
 * state is preserved.
 *
 * Taps are bucketed by local day because the daily "صلاة اليوم" counter is
 * zeroed at local midnight. Taps buffered before a reset must not inflate
 * today's number, but they *must* still reach the lifetime total — badges
 * are keyed off lifetime and are meant to be permanent.
 */
object SalawatBuffer {
    private const val PREFS = "salawat_background_taps"
    private const val KEY_DAY = "pending_day"
    private const val KEY_TODAY = "pending_today"
    private const val KEY_STALE = "pending_stale"

    /** Mirror of the app's counters, so the notification/widget can render a
     *  live number without booting a Flutter engine to ask. */
    private const val KEY_DISPLAY = "display_count"

    /** Bubble hidden until the app is next opened. See [dismissed]. */
    private const val KEY_DISMISSED = "overlay_dismissed"

    /** Where the user last parked the bubble. See [position]. */
    private const val KEY_POS_X = "overlay_pos_x"
    private const val KEY_POS_Y = "overlay_pos_y"

    private val lock = Any()

    private fun prefs(context: Context) =
        context.applicationContext.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

    private fun today(): String =
        SimpleDateFormat("yyyy-MM-dd", Locale.US).format(Date())

    /**
     * Records [n] taps and returns the display count to render afterwards.
     * Synchronized because the widget provider and the notification receiver
     * can both land here from different binder threads.
     */
    fun append(context: Context, n: Int): Int = synchronized(lock) {
        val p = prefs(context)
        val storedDay = p.getString(KEY_DAY, null)
        val today = today()

        var todayCount = p.getInt(KEY_TODAY, 0)
        var stale = p.getInt(KEY_STALE, 0)

        // Rolled past local midnight since the last background tap: retire
        // yesterday's buffered taps to the stale bucket before adding today's.
        if (storedDay != null && storedDay != today) {
            stale += todayCount
            todayCount = 0
        }
        todayCount += n

        val display = p.getInt(KEY_DISPLAY, 0) + n
        p.edit()
            .putString(KEY_DAY, today)
            .putInt(KEY_TODAY, todayCount)
            .putInt(KEY_STALE, stale)
            .putInt(KEY_DISPLAY, display)
            .apply()
        display
    }

    /**
     * Atomically hands the buffered taps to the caller and clears them.
     * Only the Flutter app calls this, on resume.
     *
     * Returns `day` alongside the counts so Dart can decide whether
     * [KEY_TODAY] still belongs to today — the app may resume on a later day
     * than the one the taps were bucketed under.
     */
    fun drain(context: Context): Map<String, Any?> = synchronized(lock) {
        val p = prefs(context)
        val result = mapOf<String, Any?>(
            "day" to p.getString(KEY_DAY, null),
            "today" to p.getInt(KEY_TODAY, 0),
            "stale" to p.getInt(KEY_STALE, 0),
        )
        p.edit()
            .remove(KEY_DAY)
            .remove(KEY_TODAY)
            .remove(KEY_STALE)
            .apply()
        result
    }

    /** Authoritative count pushed down from Dart after a drain/tap. */
    fun setDisplay(context: Context, value: Int) = synchronized(lock) {
        prefs(context).edit().putInt(KEY_DISPLAY, value).apply()
    }

    fun display(context: Context): Int = synchronized(lock) {
        prefs(context).getInt(KEY_DISPLAY, 0)
    }

    /**
     * The permanent on/off switch for the floating counter, owned by the
     * profile toggle. Flipped on once by the first-run setup in
     * `core/quick_tap_setup.dart` and otherwise left alone — dismissing the
     * bubble does *not* clear it (see [dismissed]).
     *
     * The ongoing notification is not a separate surface with its own flag.
     * Android requires one to keep the overlay's foreground service alive, so
     * it exists exactly as long as the bubble does and carries no buttons of
     * its own.
     */
    fun quickTapEnabled(context: Context): Boolean =
        prefs(context).getBoolean("quick_tap_enabled", false)

    fun setQuickTapEnabled(context: Context, value: Boolean) {
        prefs(context).edit().putBoolean("quick_tap_enabled", value).apply()
    }

    /**
     * Set when the user flicks the bubble onto the X target (or long-presses
     * it) — "not right now", not "never again".
     *
     * Kept separate from [quickTapEnabled] on purpose. Dismissing used to turn
     * the whole feature off, which meant the only way back was hunting down a
     * toggle in the profile screen, and re-granting a permission the user had
     * already granted. Now the flag is cleared the next time the app is opened
     * ([MainActivity.onResume]), so the bubble returns on its own the next time
     * the user leaves the app, with nothing to re-ask.
     */
    fun dismissed(context: Context): Boolean =
        prefs(context).getBoolean(KEY_DISMISSED, false)

    fun setDismissed(context: Context, value: Boolean) {
        prefs(context).edit().putBoolean(KEY_DISMISSED, value).apply()
    }

    /**
     * Where the bubble was last dropped, or null if the user has never moved
     * it.
     *
     * Persisted rather than held in memory because the service is stopped and
     * restarted constantly by design — every time the app is opened and left
     * again, and on boot and app update. Keeping the position in the service
     * meant it reset to the top-left corner on every one of those, so moving
     * the bubble out of the way never actually stuck.
     */
    fun position(context: Context): Pair<Int, Int>? {
        val p = prefs(context)
        if (!p.contains(KEY_POS_X)) return null
        return p.getInt(KEY_POS_X, 0) to p.getInt(KEY_POS_Y, 0)
    }

    fun setPosition(context: Context, x: Int, y: Int) {
        prefs(context).edit().putInt(KEY_POS_X, x).putInt(KEY_POS_Y, y).apply()
    }

    /** Arabic-Indic digits, matching `core/arabic_numbers.dart` in the app. */
    fun formatArabic(value: Int): String {
        val western = String.format(Locale.US, "%,d", value)
        val sb = StringBuilder(western.length)
        for (c in western) {
            sb.append(
                when (c) {
                    in '0'..'9' -> '٠' + (c - '0')
                    ',' -> '٬'
                    else -> c
                }
            )
        }
        return sb.toString()
    }
}
