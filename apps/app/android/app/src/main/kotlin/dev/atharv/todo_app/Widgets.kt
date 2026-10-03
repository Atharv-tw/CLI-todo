package dev.atharv.todo_app

import android.app.AlarmManager
import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.graphics.Paint
import android.net.Uri
import android.os.SystemClock
import android.view.View
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetBackgroundIntent
import es.antonborri.home_widget.HomeWidgetBackgroundReceiver
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import es.antonborri.home_widget.HomeWidgetProvider
import java.time.Instant
import java.time.LocalDate
import org.json.JSONArray
import org.json.JSONObject

// The Flutter side stores one JSON snapshot of the day (see Store.snapshot);
// these providers only draw it and turn taps into `todo://` actions that the
// Dart `widgetAction` callback handles.

private fun snapshot(data: SharedPreferences): JSONObject? =
    data.getString("snapshot", null)?.let { runCatching { JSONObject(it) }.getOrNull() }

private fun action(context: Context, uri: String): PendingIntent =
    HomeWidgetBackgroundIntent.getBroadcast(context, Uri.parse(uri))

private fun openApp(context: Context): PendingIntent =
    HomeWidgetLaunchIntent.getActivity(context, MainActivity::class.java)

/** A scrolling list of tickable rows; each item's `kind` and `id` form its tap action. */
private fun listViews(
    context: Context,
    title: String,
    items: JSONArray,
    emptyText: String,
    footer: String?,
): RemoteViews {
  val views = RemoteViews(context.packageName, R.layout.widget_list)
  views.setTextViewText(R.id.title, title)
  views.setOnClickPendingIntent(R.id.title, openApp(context))

  val rows = RemoteViews.RemoteCollectionItems.Builder().setHasStableIds(true).setViewTypeCount(1)
  for (i in 0 until items.length()) {
    val item = items.getJSONObject(i)
    val done = item.getBoolean("done")
    val time = if (item.isNull("time")) "" else item.optString("time")
    val row = RemoteViews(context.packageName, R.layout.widget_row)
    row.setTextViewText(R.id.row_check, if (done) "✓" else "○")
    row.setTextViewText(R.id.row_time, time)
    row.setViewVisibility(R.id.row_time, if (time.isEmpty()) View.GONE else View.VISIBLE)
    row.setTextViewText(R.id.row_text, item.getString("title"))
    row.setTextColor(
        R.id.row_text,
        context.getColor(if (done) R.color.widget_muted else R.color.widget_ink),
    )
    row.setInt(
        R.id.row_text,
        "setPaintFlags",
        Paint.ANTI_ALIAS_FLAG or (if (done) Paint.STRIKE_THRU_TEXT_FLAG else 0),
    )
    val kind = item.optString("kind", "task")
    row.setOnClickFillInIntent(
        R.id.row,
        Intent().setData(Uri.parse("todo://$kind/toggle?id=${item.getString("id")}")),
    )
    rows.addItem(item.getString("id").hashCode().toLong(), row)
  }
  views.setRemoteAdapter(R.id.rows, rows.build())

  // Rows fill in their own `todo://` uri on top of this shared template.
  val template =
      Intent(context, HomeWidgetBackgroundReceiver::class.java)
          .setAction("es.antonborri.home_widget.action.BACKGROUND")
  views.setPendingIntentTemplate(
      R.id.rows,
      PendingIntent.getBroadcast(
          context,
          2,
          template,
          PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_MUTABLE,
      ),
  )

  val notes = listOfNotNull(if (items.length() == 0) emptyText else null, footer)
  views.setViewVisibility(R.id.footer, if (notes.isEmpty()) View.GONE else View.VISIBLE)
  views.setTextViewText(R.id.footer, notes.joinToString(" · "))
  views.setOnClickPendingIntent(R.id.footer, openApp(context))
  return views
}

private fun placeholder(context: Context, title: String): RemoteViews =
    listViews(context, title, JSONArray(), "Open the app to load today", null)

/** A snapshot from an earlier day is stale: say so rather than show old ticks. */
private fun isToday(snap: JSONObject) = snap.optString("date") == LocalDate.now().toString()

class TodayWidget : HomeWidgetProvider() {
  override fun onUpdate(
      context: Context,
      appWidgetManager: AppWidgetManager,
      appWidgetIds: IntArray,
      widgetData: SharedPreferences,
  ) {
    val snap = snapshot(widgetData)
    val views =
        if (snap == null || !isToday(snap)) {
          placeholder(context, "Today")
        } else {
          val items = snap.getJSONArray("items")
          val done = (0 until items.length()).count { items.getJSONObject(it).getBoolean("done") }
          val overdue = snap.optInt("overdue")
          listViews(
              context,
              "Today  $done/${items.length()}",
              items,
              "Nothing scheduled",
              if (overdue > 0) "$overdue overdue" else null,
          )
        }
    appWidgetIds.forEach { appWidgetManager.updateAppWidget(it, views) }
  }
}

class HabitsWidget : HomeWidgetProvider() {
  override fun onUpdate(
      context: Context,
      appWidgetManager: AppWidgetManager,
      appWidgetIds: IntArray,
      widgetData: SharedPreferences,
  ) {
    val snap = snapshot(widgetData)
    val views =
        if (snap == null || !isToday(snap)) {
          placeholder(context, "Habits")
        } else {
          val habits = snap.getJSONArray("habits")
          val done = (0 until habits.length()).count { habits.getJSONObject(it).getBoolean("done") }
          for (i in 0 until habits.length()) habits.getJSONObject(i).put("kind", "habit")
          listViews(context, "Habits  $done/${habits.length()}", habits, "No habits today", null)
        }
    appWidgetIds.forEach { appWidgetManager.updateAppWidget(it, views) }
  }
}

class FocusWidget : HomeWidgetProvider() {
  override fun onUpdate(
      context: Context,
      appWidgetManager: AppWidgetManager,
      appWidgetIds: IntArray,
      widgetData: SharedPreferences,
  ) {
    val snap = snapshot(widgetData)
    val focus = snap?.optJSONObject("focus")
    val endsAt =
        focus?.let { runCatching { Instant.parse(it.getString("ends_at")).toEpochMilli() }.getOrNull() }
    val leftMs = if (endsAt == null) 0 else endsAt - System.currentTimeMillis()
    val views = RemoteViews(context.packageName, R.layout.widget_focus)
    views.setOnClickPendingIntent(R.id.focus_label, openApp(context))

    if (focus != null && leftMs > 0) {
      val isBreak = focus.optString("kind") == "break"
      val task = if (focus.isNull("task")) null else focus.optString("task")
      views.setTextViewText(R.id.focus_label, if (isBreak) "Break" else task ?: "Focus")
      views.setViewVisibility(R.id.focus_timer, View.VISIBLE)
      views.setViewVisibility(R.id.focus_idle, View.GONE)
      views.setChronometerCountDown(R.id.focus_timer, true)
      views.setChronometer(R.id.focus_timer, SystemClock.elapsedRealtime() + leftMs, null, true)
      views.setTextViewText(R.id.focus_button, "Stop")
      views.setOnClickPendingIntent(R.id.focus_button, action(context, "todo://focus/stop"))

      // Redraw when the session ends so the countdown does not run past zero.
      val redraw =
          Intent(context, FocusWidget::class.java)
              .setAction(AppWidgetManager.ACTION_APPWIDGET_UPDATE)
              .putExtra(AppWidgetManager.EXTRA_APPWIDGET_IDS, appWidgetIds)
      val pending =
          PendingIntent.getBroadcast(
              context,
              1,
              redraw,
              PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
          )
      (context.getSystemService(Context.ALARM_SERVICE) as AlarmManager).setAndAllowWhileIdle(
          AlarmManager.RTC,
          endsAt!! + 500,
          pending,
      )
    } else {
      val minutes = if (snap != null && isToday(snap)) snap.optInt("focused_min") else 0
      views.setTextViewText(R.id.focus_label, "Focus")
      views.setViewVisibility(R.id.focus_timer, View.GONE)
      views.setChronometer(R.id.focus_timer, SystemClock.elapsedRealtime(), null, false)
      views.setViewVisibility(R.id.focus_idle, View.VISIBLE)
      views.setTextViewText(R.id.focus_idle, "$minutes min today")
      views.setTextViewText(R.id.focus_button, "Start 25 min")
      views.setOnClickPendingIntent(R.id.focus_button, action(context, "todo://focus/start"))
    }
    appWidgetIds.forEach { appWidgetManager.updateAppWidget(it, views) }
  }
}
