package dev.atharv.todo_app

import android.app.AppOpsManager
import android.app.usage.UsageEvents
import android.app.usage.UsageStatsManager
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.Process
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "todo/usage").setMethodCallHandler { call, result ->
            when (call.method) {
                "hasAccess" -> result.success(hasUsageAccess())
                "openSettings" -> {
                    startActivity(Intent(Settings.ACTION_USAGE_ACCESS_SETTINGS).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
                    result.success(null)
                }
                "deviceName" -> result.success(Build.MODEL)
                "spans" -> {
                    val from = (call.argument<Number>("from") ?: 0).toLong()
                    val to = (call.argument<Number>("to") ?: System.currentTimeMillis()).toLong()
                    result.success(foregroundSpans(from, to))
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun hasUsageAccess(): Boolean {
        val ops = getSystemService(Context.APP_OPS_SERVICE) as AppOpsManager
        val mode = ops.unsafeCheckOpNoThrow(AppOpsManager.OPSTR_GET_USAGE_STATS, Process.myUid(), packageName)
        return mode == AppOpsManager.MODE_ALLOWED
    }

    /** Apps that are not "using the phone": the home screen and system chrome. */
    private fun ignoredPackages(): Set<String> {
        val home = packageManager.resolveActivity(
            Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_HOME), 0
        )?.activityInfo?.packageName
        return setOfNotNull(home, "com.android.systemui")
    }

    private fun label(pkg: String): String = try {
        packageManager.getApplicationLabel(packageManager.getApplicationInfo(pkg, 0)).toString()
    } catch (e: Exception) {
        pkg
    }

    /**
     * Foreground stretches in [from, to] as {app, name, start, end} (epoch ms).
     * An app is in front from the moment one of its activities resumes until
     * another app takes over or the screen turns off.
     */
    private fun foregroundSpans(from: Long, to: Long): List<Map<String, Any>> {
        val manager = getSystemService(Context.USAGE_STATS_SERVICE) as UsageStatsManager
        val events = manager.queryEvents(from, to)
        val ignored = ignoredPackages()
        val names = HashMap<String, String>()
        val spans = ArrayList<Map<String, Any>>()
        var current: String? = null
        var activity: String? = null
        var since = 0L

        fun close(at: Long) {
            val pkg = current ?: return
            if (at > since && pkg !in ignored) {
                spans.add(mapOf("app" to pkg, "name" to names.getOrPut(pkg) { label(pkg) }, "start" to since, "end" to at))
            }
            current = null
        }

        val e = UsageEvents.Event()
        while (events.hasNextEvent()) {
            events.getNextEvent(e)
            when (e.eventType) {
                UsageEvents.Event.ACTIVITY_RESUMED -> {
                    if (current != e.packageName) {
                        close(e.timeStamp)
                        current = e.packageName
                        since = e.timeStamp
                    }
                    activity = e.className
                }
                // Moving between two screens of one app pauses the old one
                // after the new one resumes; that is not leaving the app.
                UsageEvents.Event.ACTIVITY_PAUSED ->
                    if (current == e.packageName && activity == e.className) close(e.timeStamp)
                UsageEvents.Event.SCREEN_NON_INTERACTIVE,
                UsageEvents.Event.KEYGUARD_SHOWN,
                UsageEvents.Event.DEVICE_SHUTDOWN -> close(e.timeStamp)
            }
        }
        // Still in front right now.
        close(minOf(to, System.currentTimeMillis()))
        return spans
    }
}
