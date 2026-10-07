import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:home_widget/home_widget.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:todo_core/todo_core.dart';

const _widgets = ['TodayWidget', 'HabitsWidget', 'FocusWidget'];
const _ongoingId = 1;
const _finishedId = 2;

final _notifications = FlutterLocalNotificationsPlugin();
bool _notificationsReady = false;

Future<void> _initNotifications() async {
  if (_notificationsReady) return;
  await _notifications.initialize(
    settings: const InitializationSettings(android: AndroidInitializationSettings('ic_stat_todo')),
  );
  _notificationsReady = true;
}

/// Asks for permission to show notifications (Android 13+). Call from the UI.
Future<void> requestNotificationPermission() async {
  if (!Platform.isAndroid) return;
  await _initNotifications();
  await _notifications
      .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
      ?.requestNotificationsPermission();
}

/// Pushes the current state to the home-screen widgets and the focus
/// notification. Phone only; a no-op elsewhere.
Future<void> refreshOutputs(Store store) async {
  if (!Platform.isAndroid) return;
  await HomeWidget.saveWidgetData('snapshot', jsonEncode(store.snapshot()));
  for (final w in _widgets) {
    await HomeWidget.updateWidget(qualifiedAndroidName: 'dev.atharv.todo_app.$w');
  }
  await _focusNotification(store);
  await _scheduleReminders(store);
}

const _reminderBase = 1000;
const _maxReminders = 60;

/// Schedules an alert at the start of each upcoming task and timed habit.
///
/// Tasks alert on the "Task reminders" channel: sound (or vibration when the
/// phone is on vibrate), shown over the lock screen, with a countdown to the
/// task's end. Habits use a quieter channel.
Future<void> _scheduleReminders(Store store) async {
  final now = DateTime.now();
  final items = [
    for (final i in store.upcoming(fromDate: today(now), days: 3))
      if (atTime(i['date'] as String, i['time'] as String).isAfter(now)) i,
  ].take(_maxReminders).toList();

  final plan = jsonEncode(items);
  if (plan == store.getMeta('reminders_plan')) return;
  await _initNotifications();
  // Only alerts that have not fired yet; ones already showing stay put.
  for (final pending in await _notifications.pendingNotificationRequests()) {
    if (pending.id >= _reminderBase) await _notifications.cancel(id: pending.id);
  }

  for (final (index, i) in items.indexed) {
    final date = i['date'] as String, time = i['time'] as String;
    final isTask = i['kind'] == 'task';
    final start = atTime(date, time);
    final end = slotEnd(date, time, i['end_time'] as String?);
    final details = isTask
        ? AndroidNotificationDetails(
            'task_start',
            'Task reminders',
            channelDescription: 'When a scheduled task starts',
            importance: Importance.max,
            priority: Priority.max,
            category: AndroidNotificationCategory.reminder,
            visibility: NotificationVisibility.public,
            fullScreenIntent: true,
            enableVibration: true,
            when: end.millisecondsSinceEpoch,
            usesChronometer: true,
            chronometerCountDown: true,
            timeoutAfter: end.difference(start).inMilliseconds,
          )
        : const AndroidNotificationDetails(
            'habit_reminder',
            'Habit reminders',
            channelDescription: 'When a habit with a time of day is due',
            importance: Importance.high,
            priority: Priority.high,
            category: AndroidNotificationCategory.reminder,
            visibility: NotificationVisibility.public,
            enableVibration: true,
          );
    Future<void> schedule(AndroidScheduleMode mode) => _notifications.zonedSchedule(
          id: _reminderBase + index,
          title: i['title'] as String,
          body: isTask ? 'Now until ${hm(end)}' : 'Habit',
          scheduledDate: tz.TZDateTime.from(start.toUtc(), tz.UTC),
          androidScheduleMode: mode,
          notificationDetails: NotificationDetails(android: details),
        );
    try {
      await schedule(AndroidScheduleMode.exactAllowWhileIdle);
    } on PlatformException {
      await schedule(AndroidScheduleMode.inexactAllowWhileIdle);
    }
  }
  store.setMeta('reminders_plan', plan);
}

Future<void> _focusNotification(Store store) async {
  final session = store.currentFocus();
  // Remember which session the notification is for, so repeated refreshes
  // neither re-alert nor leave a stale timer behind.
  final shown = store.getMeta('notified_focus');
  if (session?.id == shown) return;
  await _initNotifications();
  await _notifications.cancel(id: _ongoingId);
  await _notifications.cancel(id: _finishedId);
  store.setMeta('notified_focus', session?.id);
  if (session == null) return;

  final isBreak = session.kind == 'break';
  final left = session.plannedEnd.difference(DateTime.now());
  await _notifications.show(
    id: _ongoingId,
    title: isBreak ? 'Break' : 'Focus',
    body: session.taskTitle ?? '${session.plannedMin} minutes',
    notificationDetails: NotificationDetails(
      android: AndroidNotificationDetails(
        'focus',
        'Focus timer',
        channelDescription: 'Countdown while a focus session or break is running',
        importance: Importance.low,
        priority: Priority.low,
        ongoing: true,
        autoCancel: false,
        onlyAlertOnce: true,
        usesChronometer: true,
        chronometerCountDown: true,
        when: session.plannedEnd.millisecondsSinceEpoch,
        timeoutAfter: left.inMilliseconds,
        category: AndroidNotificationCategory.stopwatch,
      ),
    ),
  );

  Future<void> scheduleEnd(AndroidScheduleMode mode) => _notifications.zonedSchedule(
        id: _finishedId,
        title: isBreak ? 'Break over' : 'Focus session finished',
        body: session.taskTitle ?? '${session.plannedMin} minutes done',
        scheduledDate: tz.TZDateTime.from(session.plannedEnd.toUtc(), tz.UTC),
        androidScheduleMode: mode,
        notificationDetails: const NotificationDetails(
          android: AndroidNotificationDetails(
            'focus_done',
            'Focus finished',
            channelDescription: 'Alert when a focus session or break ends',
            importance: Importance.high,
            priority: Priority.high,
            category: AndroidNotificationCategory.alarm,
          ),
        ),
      );
  try {
    await scheduleEnd(AndroidScheduleMode.exactAllowWhileIdle);
  } on PlatformException {
    // Exact alarms refused by the system: a slightly late alert beats none.
    await scheduleEnd(AndroidScheduleMode.inexactAllowWhileIdle);
  }
}
