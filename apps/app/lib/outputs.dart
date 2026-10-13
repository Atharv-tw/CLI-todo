import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:home_widget/home_widget.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:todo_core/todo_core.dart';

import 'reminders.dart';

const _widgets = ['TodayWidget', 'HabitsWidget', 'FocusWidget'];
const _ongoingId = 1;
const _finishedId = 2;

/// Pushes the current state to the home-screen widgets and the focus
/// notification. Phone only; a no-op elsewhere.
Future<void> refreshOutputs(Store store) async {
  if (!Platform.isAndroid) return;
  await HomeWidget.saveWidgetData('snapshot', jsonEncode(store.snapshot()));
  for (final w in _widgets) {
    await HomeWidget.updateWidget(qualifiedAndroidName: 'dev.atharv.todo_app.$w');
  }
  await _focusNotification(store);
  await scheduleReminders(store);
  await clearHandledReminders(store);
}

Future<void> _focusNotification(Store store) async {
  final session = store.currentFocus();
  // Remember which session the notification is for, so repeated refreshes
  // neither re-alert nor leave a stale timer behind.
  final shown = store.getMeta('notified_focus');
  if (session?.id == shown) return;
  await initNotifications();
  await notifications.cancel(id: _ongoingId);
  await notifications.cancel(id: _finishedId);
  store.setMeta('notified_focus', session?.id);
  if (session == null) return;

  final isBreak = session.kind == 'break';
  final left = session.plannedEnd.difference(DateTime.now());
  await notifications.show(
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

  Future<void> scheduleEnd(AndroidScheduleMode mode) => notifications.zonedSchedule(
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
