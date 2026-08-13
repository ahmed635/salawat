package com.salawat.app

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.widget.RemoteViews

/**
 * Home-screen widget: the running count plus one big tap target.
 *
 * The whole card routes to [TapReceiver], the same entry point the
 * notification action uses, so both surfaces append through one code path.
 */
class SalawatWidgetProvider : AppWidgetProvider() {

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
    ) {
        for (id in appWidgetIds) {
            render(context, appWidgetManager, id)
        }
    }

    companion object {
        /** Re-render every placed instance. Safe when none exist. */
        fun renderAll(context: Context) {
            val manager = AppWidgetManager.getInstance(context) ?: return
            val ids = manager.getAppWidgetIds(
                ComponentName(context, SalawatWidgetProvider::class.java)
            )
            for (id in ids) render(context, manager, id)
        }

        private fun render(
            context: Context,
            manager: AppWidgetManager,
            widgetId: Int,
        ) {
            val count = SalawatBuffer.display(context)
            val views = RemoteViews(context.packageName, R.layout.widget_salawat)
            views.setTextViewText(R.id.widget_count, SalawatBuffer.formatArabic(count))

            val tapIntent = Intent(context, TapReceiver::class.java).apply {
                action = TapReceiver.ACTION_TAP
                putExtra(TapReceiver.EXTRA_SOURCE, "widget")
            }
            val pending = PendingIntent.getBroadcast(
                context,
                0,
                tapIntent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )
            views.setOnClickPendingIntent(R.id.widget_root, pending)

            manager.updateAppWidget(widgetId, views)
        }
    }
}
