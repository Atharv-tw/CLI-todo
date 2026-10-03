import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:todo_core/todo_core.dart';
import 'package:workmanager/workmanager.dart';

import 'calendar_sync.dart';
import 'outputs.dart';

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

/// Runs when something on a home-screen widget is tapped, without the app open.
@pragma('vm:entry-point')
Future<void> widgetAction(Uri? uri) async {
  if (uri == null) return;
  final db = openDb(await appDbPath());
  try {
    final store = Store(db);
    final id = uri.queryParameters['id'];
    switch (uri.host) {
      case 'task' when id != null:
        store.setDone(id, !store.task(id).done);
      case 'habit' when id != null:
        store.setHabitCheck(id, today(), !store.checkedHabitIds(today()).contains(id));
      case 'focus':
        uri.path == '/start' ? store.startFocus() : store.stopFocus();
    }
    await refreshOutputs(store);
    await _quietSync(store);
    await refreshOutputs(store);
  } finally {
    db.close();
  }
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
