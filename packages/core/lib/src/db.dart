import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';

/// Laptop location of the shared database. The desktop app, the CLI and the
/// GNOME widget all open this same file; `TODO_DB` overrides it.
String defaultDbPath() {
  final env = Platform.environment;
  final override = env['TODO_DB'];
  if (override != null && override.isNotEmpty) return override;
  final data =
      env['XDG_DATA_HOME'] ?? p.join(env['HOME'] ?? '.', '.local', 'share');
  return p.join(data, 'todo', 'todo.db');
}

Database openDb([String? path]) {
  path ??= defaultDbPath();
  final dir = Directory(p.dirname(path));
  if (!dir.existsSync()) {
    dir.createSync(recursive: true);
    // The database also holds the sync session, so keep the folder private.
    if (Platform.isLinux) Process.runSync('chmod', ['700', dir.path]);
  }
  final db = sqlite3.open(path);
  db.execute('PRAGMA journal_mode = WAL');
  db.execute('PRAGMA busy_timeout = 5000');
  migrate(db);
  return db;
}

Database openMemoryDb() {
  final db = sqlite3.openInMemory();
  migrate(db);
  return db;
}

/// Tables that sync. Each has `updated_at` (client clock, used for
/// last-write-wins), `deleted_at` (tombstone) and `dirty` (needs pushing).
const syncedTables = ['lists', 'tasks', 'habits', 'habit_checks', 'focus_sessions', 'screen_usage'];

const _sync = '''
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  deleted_at TEXT,
  dirty INTEGER NOT NULL DEFAULT 1''';

const _migrations = [
  '''
  CREATE TABLE lists (
    id TEXT PRIMARY KEY,
    title TEXT NOT NULL,
    $_sync
  );
  CREATE TABLE tasks (
    id TEXT PRIMARY KEY,
    list_id TEXT,
    title TEXT NOT NULL,
    notes TEXT,
    tag TEXT,
    date TEXT,
    start_time TEXT,
    end_time TEXT,
    done_at TEXT,
    calendar_event_id TEXT,
    $_sync
  );
  CREATE INDEX tasks_date ON tasks(date);
  CREATE TABLE habits (
    id TEXT PRIMARY KEY,
    title TEXT NOT NULL,
    start_date TEXT,
    end_date TEXT,
    sort INTEGER NOT NULL DEFAULT 0,
    $_sync
  );
  CREATE TABLE habit_checks (
    id TEXT PRIMARY KEY,
    habit_id TEXT NOT NULL,
    date TEXT NOT NULL,
    done INTEGER NOT NULL,
    $_sync
  );
  CREATE INDEX habit_checks_date ON habit_checks(date);
  CREATE TABLE focus_sessions (
    id TEXT PRIMARY KEY,
    task_id TEXT,
    kind TEXT NOT NULL,
    started_at TEXT NOT NULL,
    planned_min INTEGER NOT NULL,
    ended_at TEXT,
    $_sync
  );
  CREATE TABLE meta (
    key TEXT PRIMARY KEY,
    value TEXT
  );
  ''',
  'ALTER TABLE habits ADD COLUMN time TEXT;',
  // One row per device, app and local hour; `seconds` is time in the foreground.
  '''
  CREATE TABLE screen_usage (
    id TEXT PRIMARY KEY,
    device_id TEXT NOT NULL,
    device TEXT NOT NULL,
    app TEXT NOT NULL,
    name TEXT NOT NULL,
    date TEXT NOT NULL,
    hour INTEGER NOT NULL,
    seconds INTEGER NOT NULL,
    $_sync
  );
  CREATE INDEX screen_usage_date ON screen_usage(date);
  ''',
];

void migrate(Database db) {
  var version = db.select('PRAGMA user_version').first.values.first as int;
  while (version < _migrations.length) {
    db.execute('BEGIN');
    db.execute(_migrations[version]);
    version++;
    db.execute('PRAGMA user_version = $version');
    db.execute('COMMIT');
  }
}
