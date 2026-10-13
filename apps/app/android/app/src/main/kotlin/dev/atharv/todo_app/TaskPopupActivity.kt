package dev.atharv.todo_app

import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.os.Bundle
import android.text.method.ScrollingMovementMethod
import android.view.View
import android.widget.TextView
import es.antonborri.home_widget.HomeWidgetBackgroundIntent
import es.antonborri.home_widget.HomeWidgetPlugin
import org.json.JSONArray
import org.json.JSONObject

/**
 * Where taps on a widget row land. A list in a widget can send its taps to
 * only one place, so both kinds come here:
 *
 * - `todo://task/toggle?id=…` (the tick): passed straight on to the Dart
 *   background handler; nothing is shown.
 * - `todo://task/details?id=…` (the text): a small card over the home screen
 *   with the task's time, list and notes, and a few things to do with it.
 */
class TaskPopupActivity : Activity() {
  override fun onCreate(savedInstanceState: Bundle?) {
    super.onCreate(savedInstanceState)
    val uri = intent.data
    val id = uri?.getQueryParameter("id")
    val kind = uri?.host
    if (uri == null || id == null || kind == null) return finish()
    if (uri.path != "/details") {
      run(uri)
      return finish()
    }

    val snap =
        HomeWidgetPlugin.getData(this).getString("snapshot", null)?.let {
          runCatching { JSONObject(it) }.getOrNull()
        }
    val item = snap?.let { find(it.optJSONArray(if (kind == "habit") "habits" else "items"), id) }
    if (item == null) return finish()
    // Tag, list and notes are only in the full task entries.
    val task = if (kind == "task") find(snap.optJSONArray("tasks"), id) else null
    val done = item.optBoolean("done")

    setContentView(R.layout.task_popup)
    val start = text(item, "time")
    val end = text(item, "end_time")
    val meta =
        listOfNotNull(
            start?.let { if (end == null) it else "$it–$end" },
            if (kind == "habit") "Habit" else null,
            task?.let { text(it, "tag") },
            task?.let { text(it, "list") },
        )
    show(R.id.popup_meta, meta.joinToString(" · "))
    findViewById<TextView>(R.id.popup_title).text = item.optString("title")
    show(R.id.popup_notes, task?.let { text(it, "notes") }.orEmpty())
    findViewById<TextView>(R.id.popup_notes).movementMethod = ScrollingMovementMethod()

    button(R.id.popup_done, if (done) "Mark not done" else "Mark done") {
      run(Uri.parse("todo://$kind/toggle?id=$id"))
    }
    val forOpenTask = if (kind == "task" && !done) View.VISIBLE else View.GONE
    findViewById<View>(R.id.popup_focus).visibility = forOpenTask
    findViewById<View>(R.id.popup_tomorrow).visibility = forOpenTask
    button(R.id.popup_focus, null) { run(Uri.parse("todo://focus/start?id=$id")) }
    button(R.id.popup_tomorrow, null) { run(Uri.parse("todo://task/tomorrow?id=$id")) }
    button(R.id.popup_open, null) {
      startActivity(
          Intent(this, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
      )
    }
  }

  /** Hands a `todo://` action to the Dart `widgetAction` callback. */
  private fun run(uri: Uri) = HomeWidgetBackgroundIntent.getBroadcast(this, uri).send()

  private fun find(items: JSONArray?, id: String): JSONObject? {
    if (items == null) return null
    for (i in 0 until items.length()) {
      val item = items.getJSONObject(i)
      if (item.optString("id") == id) return item
    }
    return null
  }

  /** A string field, or null when it is missing, JSON null or blank. */
  private fun text(obj: JSONObject, key: String): String? =
      if (obj.isNull(key)) null else obj.optString(key).trim().ifEmpty { null }

  private fun show(view: Int, value: String) {
    val v = findViewById<TextView>(view)
    v.text = value
    v.visibility = if (value.isEmpty()) View.GONE else View.VISIBLE
  }

  private fun button(view: Int, label: String?, onTap: () -> Unit) {
    val v = findViewById<TextView>(view)
    if (label != null) v.text = label
    v.setOnClickListener {
      onTap()
      finish()
    }
  }
}
