import 'dart:math';

import 'package:sqlite3/sqlite3.dart';

import 'dates.dart';
import 'models.dart';

class TodoException implements Exception {
  TodoException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// All reads and writes go through here so every change is stamped with
/// `updated_at` and marked dirty for the next sync.
class Store {
  Store(this.db);

  final Database db;

  static final _rng = Random.secure();

  static String newId() {
    final b = List.generate(16, (_) => _rng.nextInt(256));
    b[6] = (b[6] & 0x0f) | 0x40;
    b[8] = (b[8] & 0x3f) | 0x80;
    final h = b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();
    return '${h.substring(0, 8)}-${h.substring(8, 12)}-${h.substring(12, 16)}-'
        '${h.substring(16, 20)}-${h.substring(20)}';
  }

  static String nowUtc() => utcStamp(DateTime.now());

  String? getMeta(String key) {
    final rows = db.select('SELECT value FROM meta WHERE key = ?', [key]);
    return rows.isEmpty ? null : rows.first['value'] as String?;
  }

  void setMeta(String key, String? value) =>
      db.execute('INSERT OR REPLACE INTO meta (key, value) VALUES (?, ?)', [key, value]);

  void _insert(String table, Map<String, Object?> values) {
    final now = nowUtc();
    final row = {...values, 'created_at': now, 'updated_at': now, 'dirty': 1};
    db.execute(
      'INSERT INTO $table (${row.keys.join(', ')}) '
      'VALUES (${List.filled(row.length, '?').join(', ')})',
      row.values.toList(),
    );
  }

  void _update(String table, String id, Map<String, Object?> values) {
    final row = {...values, 'updated_at': nowUtc(), 'dirty': 1};
    db.execute(
      'UPDATE $table SET ${row.keys.map((k) => '$k = ?').join(', ')} WHERE id = ?',
      [...row.values, id],
    );
  }

  /// Full id for an id prefix, the way git resolves short hashes.
  String resolveId(String table, String ref) {
    final rows = db.select(
      'SELECT id FROM $table WHERE deleted_at IS NULL AND id LIKE ? LIMIT 2',
      ['$ref%'],
    );
    final what = table.replaceAll('_', ' ');
    if (rows.isEmpty) throw TodoException('Nothing in $what matches "$ref"');
    if (rows.length > 1) throw TodoException('"$ref" matches more than one row in $what; use more characters');
    return rows.first['id'] as String;
  }

  // Lists

  List<TaskList> lists() => db
      .select('SELECT * FROM lists WHERE deleted_at IS NULL ORDER BY created_at')
      .map(TaskList.fromRow)
      .toList();

  /// By title (case-insensitive), else by id prefix.
  TaskList? findList(String ref) {
    final byTitle = db.select(
      'SELECT * FROM lists WHERE deleted_at IS NULL AND lower(title) = lower(?)',
      [ref],
    );
    if (byTitle.isNotEmpty) return TaskList.fromRow(byTitle.first);
    final byId = db.select(
      'SELECT * FROM lists WHERE deleted_at IS NULL AND id LIKE ?',
      ['$ref%'],
    );
    return byId.length == 1 ? TaskList.fromRow(byId.first) : null;
  }

  TaskList ensureList(String title) {
    final existing = findList(title);
    if (existing != null) return existing;
    final id = newId();
    _insert('lists', {'id': id, 'title': title});
    return findList(id)!;
  }

  // Tasks

  static const _taskSelect =
      'SELECT t.*, l.title AS list_title FROM tasks t LEFT JOIN lists l ON l.id = t.list_id';

  Task task(String id) =>
      Task.fromRow(db.select('$_taskSelect WHERE t.id = ?', [id]).first);

  Task addTask({
    required String title,
    String? listId,
    String? date,
    String? startTime,
    String? endTime,
    String? tag,
    String? notes,
  }) {
    if (title.trim().isEmpty) throw TodoException('A task needs a title');
    final id = newId();
    _insert('tasks', {
      'id': id,
      'list_id': listId,
      'title': title.trim(),
      'notes': notes,
      'tag': tag,
      'date': date,
      'start_time': startTime,
      'end_time': endTime,
    });
    return task(id);
  }

  /// Tasks dated within [from]..[to] (either end optional). [undated] adds
  /// tasks with no date; [overdueBefore] restricts to open tasks dated earlier.
  List<Task> tasks({
    String? from,
    String? to,
    String? listId,
    bool includeDone = true,
    bool undated = false,
    String? overdueBefore,
  }) {
    final where = ['t.deleted_at IS NULL'];
    final args = <Object?>[];
    if (overdueBefore != null) {
      where.add('t.date < ? AND t.done_at IS NULL');
      args.add(overdueBefore);
    } else if (from != null || to != null) {
      final range = [
        if (from != null) 't.date >= ?',
        if (to != null) 't.date <= ?',
      ].join(' AND ');
      where.add(undated ? '(t.date IS NULL OR ($range))' : '($range)');
      args.addAll([?from, ?to]);
    } else if (!undated) {
      where.add('t.date IS NOT NULL');
    }
    if (listId != null) {
      where.add('t.list_id = ?');
      args.add(listId);
    }
    if (!includeDone) where.add('t.done_at IS NULL');
    return db
        .select(
          '$_taskSelect WHERE ${where.join(' AND ')} '
          'ORDER BY t.date IS NULL, t.date, t.start_time IS NULL, t.start_time, t.created_at, t.rowid',
          args,
        )
        .map(Task.fromRow)
        .toList();
  }

  Task setDone(String id, bool done) {
    _update('tasks', id, {'done_at': done ? nowUtc() : null});
    return task(id);
  }

  static const _editable = {
    'title', 'notes', 'tag', 'date', 'start_time', 'end_time', 'list_id', 'calendar_event_id',
  };

  /// [changes] maps column name to new value; a null value clears the field.
  Task updateTask(String id, Map<String, Object?> changes) {
    final bad = changes.keys.where((k) => !_editable.contains(k));
    if (bad.isNotEmpty) throw TodoException('Cannot edit: ${bad.join(', ')}');
    if (changes.isNotEmpty) _update('tasks', id, changes);
    return task(id);
  }

  void deleteTask(String id) => _update('tasks', id, {'deleted_at': nowUtc()});

  // Habits

  Habit addHabit({required String title, String? time, String? startDate, String? endDate}) {
    if (title.trim().isEmpty) throw TodoException('A habit needs a title');
    final id = newId();
    final sort = db.select('SELECT coalesce(max(sort), 0) + 1 AS n FROM habits').first['n'];
    _insert('habits', {
      'id': id,
      'title': title.trim(),
      'time': time,
      'start_date': startDate,
      'end_date': endDate,
      'sort': sort,
    });
    return Habit.fromRow(db.select('SELECT * FROM habits WHERE id = ?', [id]).first);
  }

  /// Habits, optionally only those whose date range covers [activeOn].
  List<Habit> habits({String? activeOn}) {
    final range = activeOn == null
        ? ''
        : 'AND (start_date IS NULL OR start_date <= ?1) AND (end_date IS NULL OR end_date >= ?1)';
    return db
        .select(
          'SELECT * FROM habits WHERE deleted_at IS NULL $range ORDER BY time IS NULL, time, sort',
          [?activeOn],
        )
        .map(Habit.fromRow)
        .toList();
  }

  /// Habit by exact title (case-insensitive), else by id prefix.
  String resolveHabit(String ref) {
    final byTitle = db.select(
      'SELECT id FROM habits WHERE deleted_at IS NULL AND lower(title) = lower(?)',
      [ref],
    );
    if (byTitle.length == 1) return byTitle.first['id'] as String;
    return resolveId('habits', ref);
  }

  void setHabitCheck(String habitId, String date, bool done) {
    final id = '$habitId:$date';
    final exists = db.select('SELECT 1 FROM habit_checks WHERE id = ?', [id]).isNotEmpty;
    if (exists) {
      _update('habit_checks', id, {'done': done ? 1 : 0});
    } else {
      _insert('habit_checks', {'id': id, 'habit_id': habitId, 'date': date, 'done': done ? 1 : 0});
    }
  }

  Set<String> checkedHabitIds(String date) => db
      .select('SELECT habit_id FROM habit_checks WHERE date = ? AND done = 1 AND deleted_at IS NULL', [date])
      .map((r) => r['habit_id'] as String)
      .toSet();

  /// Sets or (with null) clears the habit's time of day.
  void setHabitTime(String id, String? time) => _update('habits', id, {'time': time});

  void deleteHabit(String id) => _update('habits', id, {'deleted_at': nowUtc()});

  // Focus

  static const _focusSelect =
      'SELECT f.*, t.title AS task_title FROM focus_sessions f LEFT JOIN tasks t ON t.id = f.task_id';

  /// The running session, if any. A session left running past its planned
  /// end is closed at that planned end, so a forgotten timer logs its
  /// planned length and no more.
  FocusSession? currentFocus() {
    final rows = db.select(
      '$_focusSelect WHERE f.ended_at IS NULL AND f.deleted_at IS NULL ORDER BY f.started_at DESC',
    );
    FocusSession? running;
    for (final row in rows) {
      final s = FocusSession.fromRow(row);
      if (running == null && DateTime.now().isBefore(s.plannedEnd)) {
        running = s;
      } else {
        _update('focus_sessions', s.id, {'ended_at': utcStamp(s.plannedEnd)});
      }
    }
    return running;
  }

  FocusSession startFocus({String? taskId, int minutes = 25, String kind = 'focus'}) {
    if (minutes < 1 || minutes > 600) throw TodoException('Minutes must be between 1 and 600');
    stopFocus();
    final id = newId();
    _insert('focus_sessions', {
      'id': id,
      'task_id': taskId,
      'kind': kind,
      'started_at': nowUtc(),
      'planned_min': minutes,
    });
    return FocusSession.fromRow(db.select('$_focusSelect WHERE f.id = ?', [id]).first);
  }

  /// Ends the running session now; returns it, or null if none was running.
  FocusSession? stopFocus() {
    final running = currentFocus();
    if (running == null) return null;
    _update('focus_sessions', running.id, {'ended_at': nowUtc()});
    return FocusSession.fromRow(db.select('$_focusSelect WHERE f.id = ?', [running.id]).first);
  }

  /// Whole minutes of focus (not breaks) in sessions started on local [date].
  int focusedMinutes(String date) {
    currentFocus();
    final dayStart = parseYmd(date);
    final dayEnd = DateTime(dayStart.year, dayStart.month, dayStart.day + 1);
    final rows = db.select(
      "SELECT * FROM focus_sessions WHERE kind = 'focus' AND deleted_at IS NULL "
      'AND started_at >= ? AND started_at < ?',
      [utcStamp(dayStart), utcStamp(dayEnd)],
    );
    var seconds = 0;
    for (final row in rows) {
      final s = FocusSession.fromRow(row);
      seconds += (s.endedAt ?? DateTime.now()).difference(s.startedAt).inSeconds;
    }
    return seconds ~/ 60;
  }

  // Reminders

  /// Unticked tasks and habits with a time of day, from [fromDate] for
  /// [days] days, each as {key, kind, title, date, time, end_time, tag}.
  List<Map<String, Object?>> upcoming({required String fromDate, int days = 3}) {
    final out = <Map<String, Object?>>[];
    for (var d = 0; d < days; d++) {
      final date = addDays(fromDate, d);
      for (final i in (snapshot(date)['items'] as List).cast<Map<String, Object?>>()) {
        if (i['time'] == null || i['done'] == true) continue;
        out.add({...i, 'date': date, 'key': '$date ${i['id']}'});
      }
    }
    return out;
  }

  // Widgets

  /// Everything a widget needs for one day, as plain JSON.
  Map<String, Object?> snapshot([String? date]) {
    date ??= today();
    final dayTasks = tasks(from: date, to: date);
    final checked = checkedHabitIds(date);
    final dayHabits = habits(activeOn: date);
    // One timeline: tasks and habits together in time order, untimed last.
    final items = <Map<String, Object?>>[
      for (final t in dayTasks)
        {'kind': 'task', 'id': t.id, 'title': t.title, 'time': t.startTime, 'end_time': t.endTime, 'done': t.done},
      for (final h in dayHabits)
        {'kind': 'habit', 'id': h.id, 'title': h.title, 'time': h.time, 'end_time': null, 'done': checked.contains(h.id)},
    ];
    int rank(Map<String, Object?> i) => i['time'] == null ? 1 : 0;
    final order = {for (var i = 0; i < items.length; i++) items[i]: i};
    items.sort((a, b) {
      final byTimed = rank(a).compareTo(rank(b));
      if (byTimed != 0) return byTimed;
      final byTime = ((a['time'] ?? '') as String).compareTo((b['time'] ?? '') as String);
      return byTime != 0 ? byTime : order[a]!.compareTo(order[b]!);
    });
    return {
      'date': date,
      'items': items,
      'open': dayTasks.where((t) => !t.done).length,
      'done': dayTasks.where((t) => t.done).length,
      'overdue': tasks(overdueBefore: date).length,
      'tasks': [for (final t in dayTasks) t.toJson()],
      'habits': [
        for (final h in dayHabits)
          {'id': h.id, 'title': h.title, 'time': h.time, 'done': checked.contains(h.id)},
      ],
      'focus': currentFocus()?.toJson(),
      'focused_min': focusedMinutes(date),
    };
  }
}
