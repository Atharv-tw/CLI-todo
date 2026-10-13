import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:todo_core/todo_core.dart';

import 'background.dart';

final notifications = FlutterLocalNotificationsPlugin();
Future<void>? _ready;

/// Set by the UI: called when a reminder is tapped, or when the system shows
/// it full screen because the phone was locked.
void Function(Reminder reminder)? onReminderOpened;

/// Must run in every isolate before [notifications] is used.
Future<void> initNotifications() => _ready ??= notifications.initialize(
      settings: const InitializationSettings(android: AndroidInitializationSettings('ic_stat_todo')),
      onDidReceiveNotificationResponse: (response) {
        final reminder = Reminder.fromPayload(response.payload);
        if (reminder != null) onReminderOpened?.call(reminder);
      },
      onDidReceiveBackgroundNotificationResponse: reminderAction,
    );

const snoozeFor = Duration(minutes: 10);

// Notification ids. Each reminder gets a stable id from its day and item, so
// it can be found again to cancel; snoozed copies live in their own range.
const _reminderBase = 1000;
const _snoozeBase = 2000000;
const _idSpan = 900000;
const _maxReminders = 60;

/// One alert: a task or timed habit on a given day.
class Reminder {
  const Reminder({
    required this.kind,
    required this.id,
    required this.date,
    required this.title,
    required this.start,
    this.end,
  });

  /// From an entry of `Store.upcoming`.
  Reminder.fromItem(Map<String, Object?> i)
      : kind = i['kind'] as String,
        id = i['id'] as String,
        date = i['date'] as String,
        title = i['title'] as String,
        start = i['time'] as String,
        end = i['end_time'] as String?;

  static const doneAction = 'done';
  static const snoozeAction = 'snooze';

  /// `task` or `habit`.
  final String kind;
  final String id;
  final String date;
  final String title;
  final String start;
  final String? end;

  bool get isTask => kind == 'task';
  String get key => '$date $id';
  DateTime get startAt => atTime(date, start);
  DateTime get endAt => slotEnd(date, start, end);

  int get _slot {
    // FNV-1a: the same on every run and in every isolate, unlike hashCode.
    var h = 0x811c9dc5;
    for (final c in key.codeUnits) {
      h = ((h ^ c) * 0x01000193) & 0x7fffffff;
    }
    return h % _idSpan;
  }

  int get notificationId => _reminderBase + _slot;
  int get snoozeId => _snoozeBase + _slot;

  String get payload =>
      jsonEncode({'kind': kind, 'id': id, 'date': date, 'title': title, 'start': start, 'end': end});

  static Reminder? fromPayload(String? payload) {
    if (payload == null || payload.isEmpty) return null;
    try {
      final m = jsonDecode(payload) as Map<String, Object?>;
      return Reminder(
        kind: m['kind'] as String,
        id: m['id'] as String,
        date: m['date'] as String,
        title: m['title'] as String,
        start: m['start'] as String,
        end: m['end'] as String?,
      );
    } catch (_) {
      return null;
    }
  }

  /// Whether there is nothing left to remind about: ticked, or gone.
  bool isHandled(Store store) {
    if (isTask) return store.findTask(id)?.done ?? true;
    return store.checkedHabitIds(date).contains(id) || !store.habits(activeOn: date).any((h) => h.id == id);
  }

  void markDone(Store store) {
    if (isTask) {
      if (store.findTask(id) != null) store.setDone(id, true);
    } else {
      store.setHabitCheck(id, date, true);
    }
  }

  /// A line under the title, and the task's notes if it has any.
  ({String summary, String? notes}) describe(Store store) {
    final task = isTask ? store.findTask(id) : null;
    final summary = [
      end == null ? start : '$start–$end',
      if (!isTask) 'Habit',
      ?task?.tag,
      ?task?.list,
    ].join(' · ');
    final notes = task?.notes?.trim();
    return (summary: summary, notes: notes == null || notes.isEmpty ? null : notes);
  }
}

AndroidNotificationDetails _details(Reminder r, String bigText, DateTime firesAt) {
  const actions = [
    AndroidNotificationAction(Reminder.doneAction, 'Doing it'),
    AndroidNotificationAction(Reminder.snoozeAction, 'Snooze 10 min'),
  ];
  final style = BigTextStyleInformation(bigText);
  if (!r.isTask) {
    return AndroidNotificationDetails(
      'habit_reminder',
      'Habit reminders',
      channelDescription: 'When a habit with a time of day is due',
      importance: Importance.high,
      priority: Priority.high,
      category: AndroidNotificationCategory.reminder,
      visibility: NotificationVisibility.public,
      enableVibration: true,
      styleInformation: style,
      actions: actions,
    );
  }
  // Counts down to the end of the slot and leaves with it; a snoozed alert
  // that fires after the slot stays for half an hour instead.
  final left = r.endAt.difference(firesAt);
  final running = left > Duration.zero;
  return AndroidNotificationDetails(
    'task_alert',
    'Task reminders',
    channelDescription: 'Full-screen alert when a scheduled task starts',
    importance: Importance.max,
    priority: Priority.max,
    category: AndroidNotificationCategory.reminder,
    visibility: NotificationVisibility.public,
    // Locked or screen off: the system opens the app on the reminder screen.
    // In use: it shows this as a banner with the two buttons instead.
    fullScreenIntent: true,
    enableVibration: true,
    vibrationPattern: Int64List.fromList([0, 600, 300, 600, 300, 600]),
    when: running ? r.endAt.millisecondsSinceEpoch : null,
    usesChronometer: running,
    chronometerCountDown: running,
    timeoutAfter: (running ? left : const Duration(minutes: 30)).inMilliseconds,
    styleInformation: style,
    actions: actions,
  );
}

Future<void> _schedule(Store store, Reminder r, {required int id, required DateTime at, bool snoozed = false}) async {
  final about = r.describe(store);
  final body = snoozed ? 'Snoozed · ${about.summary}' : about.summary;
  final details = NotificationDetails(
    android: _details(r, [body, ?about.notes].join('\n'), at),
  );
  Future<void> schedule(AndroidScheduleMode mode) => notifications.zonedSchedule(
        id: id,
        title: r.title,
        body: body,
        payload: r.payload,
        scheduledDate: tz.TZDateTime.from(at.toUtc(), tz.UTC),
        androidScheduleMode: mode,
        notificationDetails: details,
      );
  try {
    await schedule(AndroidScheduleMode.exactAllowWhileIdle);
  } on PlatformException {
    // Exact alarms refused by the system: a slightly late alert beats none.
    await schedule(AndroidScheduleMode.inexactAllowWhileIdle);
  }
}

/// Schedules an alert at the start of each upcoming task and timed habit.
///
/// A task alerts on the "Task reminders" channel: sound, or vibration when
/// the phone is on vibrate, and full screen when the phone is locked. Habits
/// use a quieter banner. Both carry "Doing it" and "Snooze" buttons.
Future<void> scheduleReminders(Store store) async {
  final now = DateTime.now();
  final items = [
    for (final i in store.upcoming(fromDate: today(now), days: 3))
      if (atTime(i['date'] as String, i['time'] as String).isAfter(now)) i,
  ].take(_maxReminders).toList();

  final plan = 'v2 ${jsonEncode(items)}';
  if (plan == store.getMeta('reminders_plan')) return;
  await initNotifications();
  // Only alerts that have not fired yet; ones already showing stay put, and
  // so do snoozed ones.
  for (final pending in await notifications.pendingNotificationRequests()) {
    if (pending.id >= _reminderBase && pending.id < _snoozeBase) await notifications.cancel(id: pending.id);
  }
  for (final i in items) {
    final r = Reminder.fromItem(i);
    await _schedule(store, r, id: r.notificationId, at: r.startAt);
  }
  store.setMeta('reminders_plan', plan);
}

/// Takes the alert for [r] off the screen and drops any snoozed copy.
Future<void> clearReminder(Reminder r) async {
  if (!Platform.isAndroid) return;
  await initNotifications();
  await notifications.cancel(id: r.notificationId);
  await notifications.cancel(id: r.snoozeId);
}

/// Alerts again for [r] in [snoozeFor].
Future<void> snoozeReminder(Store store, Reminder r) async {
  if (!Platform.isAndroid) return;
  await clearReminder(r);
  await _schedule(store, r, id: r.snoozeId, at: DateTime.now().add(snoozeFor), snoozed: true);
}

/// Removes alerts, showing or snoozed, for items that have since been ticked
/// or deleted somewhere else (the app, a widget, another device).
Future<void> clearHandledReminders(Store store) async {
  await initNotifications();
  bool handled(String? payload) => Reminder.fromPayload(payload)?.isHandled(store) ?? false;
  for (final n in await notifications.getActiveNotifications()) {
    final id = n.id;
    if (id != null && id >= _reminderBase && handled(n.payload)) await notifications.cancel(id: id);
  }
  for (final p in await notifications.pendingNotificationRequests()) {
    if (p.id >= _snoozeBase && handled(p.payload)) await notifications.cancel(id: p.id);
  }
}

/// Asks for what alerts need: permission to notify (Android 13+) and, where
/// the system has withheld it, to show full screen. Call from the UI.
Future<void> requestNotificationPermission(Store store) async {
  if (!Platform.isAndroid) return;
  await initNotifications();
  final android = notifications.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
  await android?.requestNotificationsPermission();
  // The channel tasks used before reminders had buttons and a full screen.
  await android?.deleteNotificationChannel(channelId: 'task_start');
  // This opens a settings page when not yet allowed, so only ask once.
  if (store.getMeta('asked_full_screen') == null) {
    store.setMeta('asked_full_screen', '1');
    try {
      await android?.requestFullScreenIntentPermission();
    } on PlatformException {
      // Another permission request is still on screen.
    }
  }
}
