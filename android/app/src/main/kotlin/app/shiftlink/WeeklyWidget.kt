package app.shiftlink

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.Context
import android.content.Intent
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetBackgroundIntent
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import es.antonborri.home_widget.HomeWidgetPlugin

/** Widget écran d'accueil : totaux de la semaine (temps, km, sorties). */
class WeeklyWidget : AppWidgetProvider() {
    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray
    ) {
        val prefs = HomeWidgetPlugin.getData(context)
        val duration = prefs.getString("weeklyDuration", "0:00") ?: "0:00"
        val km = prefs.getString("weeklyKm", "0,0") ?: "0,0"
        val rides = prefs.getInt("weeklyRides", 0)

        appWidgetIds.forEach { id ->
            val views = RemoteViews(context.packageName, R.layout.weekly_widget).apply {
                setTextViewText(R.id.wkDuration, duration)
                setTextViewText(R.id.wkKm, km)
                setTextViewText(R.id.wkRides, rides.toString())
                val pending = HomeWidgetLaunchIntent.getActivity(
                    context,
                    MainActivity::class.java
                )
                setOnClickPendingIntent(R.id.wkRoot, pending)
            }
            appWidgetManager.updateAppWidget(id, views)
        }
    }
}
