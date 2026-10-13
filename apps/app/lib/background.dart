import 'dart:io';
import 'dart:ui';

import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:todo_core/todo_core.dart';
import 'package:workmanager/workmanager.dart';

import 'calendar_sync.dart';
import 'outputs.dart';
import 'reminders.dart';

/// On the laptop the app shares one database with the CLI and top-bar widget.
Future<String> appDbPath() async => Platform.isLinux
    ? defaultDbPath()
    : p.join((await getApplicationSupportDirectory()).path, 'todo.db');

/// Server sync plus (on the phone) calendar sync. Network errors propagate.
Future<void> fullSync(Store store) async {
  final remote = SupabaseRemote(store);
  final engine = SyncEngine(store, remote);
  if (remote.signedIn) await engine.sync();
  if (Platform.isAndroid && await CalendarSync(store).run() > 0 && remote.signedIn) {
    await engine.sync();
  }
}

Future<void> _quietSync(Store store) async {
  try {
    await fullSync(store);
  } catch (_) {
    // Offline or signed out: the change is saved and goes up next time.
  }
}

/// Background code (a widget tap, a button on a reminder) changes the
/// database from its own isolate; this is how it tells the open app to redraw.
const appChangedPort = 'todo.changed';

void _tellApp() => IsolateNameServer.lookupPortByName(appChangedPort)?.send(null);

/// Runs when something on a home-screen widget is tapped, without the app open.
@pragma('vm:entry-point')
Future<void> widgetAction(Uri? uri) async {
  if (uri == null) return;
  final db = openDb(await appDbPath());
  try {
    final store = Store(db);
    final id = uri.queryParameters['id'];
    switch (uri.host) {
      case 'task' when id != null && uri.path == '/tomorrow':
        if (store.findTask(id) != null) store.updateTask(id, {'date': addDays(today(), 1)});
      case 'task' when id != null:
        final task = store.findTask(id);
        if (task != null) store.setDone(id, !task.done);
      case 'habit' when id != null:
        store.setHabitCheck(id, today(), !store.checkedHabitIds(today()).contains(id));
      case 'focus':
        // With an id, the session is for that task.
        uri.path == '/start' ? store.startFocus(taskId: id) : store.stopFocus();
    }
    await refreshOutputs(store);
    _tellApp();
    await _quietSync(store);
    await refreshOutputs(store);
  } finally {
    db.close();
  }
  _tellApp();
}

/// Runs when "Doing it" or "Snooze" is pressed on a reminder notification,
/// whether or not the app is open.
@pragma('vm:entry-point')
Future<void> reminderAction(NotificationResponse response) async {
  DartPluginRegistrant.ensureInitialized();
  final reminder = Reminder.fromPayload(response.payload);
  if (reminder == null) return;
  final db = openDb(await appDbPath());
  try {
    final store = Store(db);
    switch (response.actionId) {
      case Reminder.doneAction:
        reminder.markDone(store);
      case Reminder.snoozeAction:
        await snoozeReminder(store, reminder);
      default:
        return;
    }
    await refreshOutputs(store);
    _tellApp();
    await _quietSync(store);
    await refreshOutputs(store);
  } finally {
    db.close();
  }
  _tellApp();
}

const _periodicTask = 'todo.sync';

/// Periodic background sync, so widgets and the calendar stay current while
/// the app is closed.
@pragma('vm:entry-point')
void backgroundWork() {
  Workmanager().executeTask((task, input) async {
    WidgetsFlutterBinding.ensureInitialized();
    final db = openDb(await appDbPath());
    try {
      final store = Store(db);
      await _quietSync(store);
      await refreshOutputs(store);
    } finally {
      db.close();
    }
    return true;
  });
}

Future<void> startBackgroundWork() async {
  if (!Platform.isAndroid) return;
  await Workmanager().initialize(backgroundWork);
  await Workmanager().registerPeriodicTask(
    _periodicTask,
    _periodicTask,
    frequency: const Duration(minutes: 15),
    existingWorkPolicy: ExistingPeriodicWorkPolicy.keep,
  );
}
