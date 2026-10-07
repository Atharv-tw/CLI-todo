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

  void renameList(String id, String title) {
    if (title.trim().isEmpty) throw TodoException('A list needs a name');
    _update('lists', id, {'title': title.trim()});
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

  // Streaks

  /// Dates in [from]..[to] on which the habit was ticked.
  Set<String> habitDays(String habitId, String from, String to) => db
      .select(
        'SELECT date FROM habit_checks WHERE habit_id = ? AND done = 1 AND deleted_at IS NULL '
        'AND date BETWEEN ? AND ?',
        [habitId, from, to],
      )
      .map((r) => r['date'] as String)
      .toSet();

  /// For each date in [from]..[to], how many of that day's tasks and active
  /// habits were completed, and how many there were. With [tasks] false,
  /// habits only.
  Map<String, ({int done, int total})> dayCompletion(String from, String to, {bool tasks = true}) {
    final taskRows = !tasks ? const <Map<String, Object?>>[] : db.select(
      'SELECT date, count(*) AS total, count(done_at) AS done FROM tasks '
      'WHERE deleted_at IS NULL AND date BETWEEN ? AND ? GROUP BY date',
      [from, to],
    );
    final tasksByDate = {for (final r in taskRows) r['date'] as String: r};
    final checkRows = db.select(
      'SELECT c.date, count(*) AS done FROM habit_checks c JOIN habits h ON h.id = c.habit_id '
      'WHERE c.done = 1 AND c.deleted_at IS NULL AND h.deleted_at IS NULL '
      'AND c.date BETWEEN ? AND ? GROUP BY c.date',
      [from, to],
    );
    final checksByDate = {for (final r in checkRows) r['date'] as String: r['done'] as int};
    final allHabits = habits();
    final out = <String, ({int done, int total})>{};
    for (var date = from; date.compareTo(to) <= 0; date = addDays(date, 1)) {
      final active = allHabits
          .where((h) =>
              (h.startDate == null || h.startDate!.compareTo(date) <= 0) &&
              (h.endDate == null || h.endDate!.compareTo(date) >= 0))
          .length;
      final t = tasksByDate[date];
      out[date] = (
        done: ((t?['done'] as int?) ?? 0) + (checksByDate[date] ?? 0),
        total: ((t?['total'] as int?) ?? 0) + active,
      );
    }
    return out;
  }

  /// Current and best run of consecutive days in [days]. A run that reached
  /// yesterday still counts as current, so today being unticked so far does
  /// not break it.
  static ({int current, int best}) streakOf(Set<String> days, String on) {
    var best = 0;
    for (final day in days) {
      if (days.contains(addDays(day, -1))) continue;
      var length = 1;
      while (days.contains(addDays(day, length))) {
        length++;
      }
      if (length > best) best = length;
    }
    var end = days.contains(on) ? on : addDays(on, -1);
    var current = 0;
    while (days.contains(end)) {
      current++;
      end = addDays(end, -1);
    }
    return (current: current, best: best);
  }

  ({int current, int best}) habitStreak(String habitId, [String? on]) {
    on ??= today();
    return streakOf(habitDays(habitId, '0000-01-01', on), on);
  }

  /// Streak of days with at least one task or habit completed (habits only
  /// with [tasks] false), over the past year.
  ({int current, int best}) overallStreak([String? on, bool tasks = true]) {
    on ??= today();
    final active = {
      for (final e in dayCompletion(addDays(on, -365), on, tasks: tasks).entries)
        if (e.value.done > 0) e.key,
    };
    return streakOf(active, on);
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

  // Screen time

  /// Stable per-install id, so two devices never write the same usage rows.
  String get deviceId {
    var id = getMeta('device_id');
    if (id == null) {
      id = newId();
      setMeta('device_id', id);
    }
    return id;
  }

  String get deviceName => getMeta('device_name') ?? 'device';

  void setDeviceName(String name) => setMeta('device_name', name);

  /// Splits [spans] at local hour boundaries into seconds per (app, date,
  /// hour), with the app's display name alongside.
  static Map<(String, String, int), (String, int)> _hourBuckets(Iterable<UsageSpan> spans) {
    // Summed in milliseconds so many short stretches do not round away.
    final millis = <(String, String, int), int>{};
    final names = <String, String>{};
    for (final s in spans) {
      names[s.app] = s.name;
      var t = s.start;
      while (t.isBefore(s.end)) {
        final next = DateTime(t.year, t.month, t.day, t.hour + 1);
        final to = next.isBefore(s.end) ? next : s.end;
        final key = (s.app, ymd(t), t.hour);
        millis[key] = (millis[key] ?? 0) + to.difference(t).inMilliseconds;
        t = to;
      }
    }
    return {
      for (final e in millis.entries)
        if (e.value >= 500) e.key: (names[e.key.$1]!, (e.value / 1000).round().clamp(1, 3600)),
    };
  }

  String _usageId(String app, String date, int hour) => '${deviceId}_${app}_${date}_$hour';

  void _writeUsage(String app, String name, String date, int hour, int seconds, {required bool add}) {
    final id = _usageId(app, date, hour);
    final old = db.select('SELECT seconds, name, deleted_at FROM screen_usage WHERE id = ?', [id]);
    if (old.isEmpty) {
      _insert('screen_usage', {
        'id': id,
        'device_id': deviceId,
        'device': deviceName,
        'app': app,
        'name': name,
        'date': date,
        'hour': hour,
        'seconds': seconds,
      });
      return;
    }
    final row = old.first;
    // An hour holds at most an hour, whatever a device reports.
    final total = add ? ((row['seconds'] as int) + seconds).clamp(0, 3600) : seconds;
    // Untouched rows stay clean, so a repeat run pushes nothing to the server.
    if (total == row['seconds'] && name == row['name'] && row['deleted_at'] == null) return;
    _update('screen_usage', id, {'seconds': total, 'name': name, 'device': deviceName, 'deleted_at': null});
  }

  void _inTransaction(void Function() body) {
    db.execute('BEGIN');
    try {
      body();
      db.execute('COMMIT');
    } catch (_) {
      db.execute('ROLLBACK');
      rethrow;
    }
  }

  /// Adds foreground time reported live (the laptop reports as it goes).
  void addUsage(Iterable<UsageSpan> spans) => _inTransaction(() {
        _hourBuckets(spans).forEach((k, v) => _writeUsage(k.$1, v.$1, k.$2, k.$3, v.$2, add: true));
      });

  /// Replaces this device's usage from [since] on with what [spans] say (the
  /// phone re-reads its own history, so running twice changes nothing).
  /// Anything in [spans] before [since] is ignored.
  void replaceUsage(DateTime since, Iterable<UsageSpan> spans) {
    final buckets = _hourBuckets([
      for (final s in spans)
        if (s.end.isAfter(since)) UsageSpan(s.app, s.name, s.start.isBefore(since) ? since : s.start, s.end),
    ]);
    _inTransaction(() {
      final seen = <String>{};
      buckets.forEach((k, v) {
        _writeUsage(k.$1, v.$1, k.$2, k.$3, v.$2, add: false);
        seen.add(_usageId(k.$1, k.$2, k.$3));
      });
      // [since] is a local midnight, so whole days are replaced.
      final stale = db.select(
        'SELECT id FROM screen_usage WHERE device_id = ? AND date >= ? AND seconds > 0 AND deleted_at IS NULL',
        [deviceId, ymd(since)],
      );
      for (final r in stale) {
        if (!seen.contains(r['id'])) _update('screen_usage', r['id'] as String, {'seconds': 0});
      }
    });
  }

  static const _usageWhere = 'deleted_at IS NULL AND seconds > 0 AND date BETWEEN ? AND ?';

  /// Apps by time, most used first, across all devices (or just [device]).
  /// An app has a different id on each platform, so the same name is one app.
  List<AppUsage> usageByApp(String from, String to, {String? device}) => db
      .select(
        'SELECT min(app) AS app, min(name) AS name, sum(seconds) AS seconds FROM screen_usage '
        'WHERE $_usageWhere ${device == null ? '' : 'AND device = ?'} '
        'GROUP BY lower(name) ORDER BY seconds DESC',
        [from, to, ?device],
      )
      .map((r) => AppUsage(r['app'] as String, r['name'] as String, r['seconds'] as int))
      .toList();

  /// Seconds for each date in [from]..[to] that has any usage.
  Map<String, int> usageByDay(String from, String to) => {
        for (final r in db.select(
          'SELECT date, sum(seconds) AS seconds FROM screen_usage WHERE $_usageWhere GROUP BY date',
          [from, to],
        ))
          r['date'] as String: r['seconds'] as int,
      };

  /// Seconds in each of the 24 hours of [date]; with [app], just that app.
  List<int> usageByHour(String date, {String? app}) {
    final hours = List.filled(24, 0);
    for (final r in db.select(
      'SELECT hour, sum(seconds) AS seconds FROM screen_usage WHERE $_usageWhere '
      '${app == null ? '' : 'AND app = ?'} GROUP BY hour',
      [date, date, ?app],
    )) {
      hours[r['hour'] as int] = r['seconds'] as int;
    }
    return hours;
  }

  /// Devices that have reported usage, with their total seconds in range.
  Map<String, int> usageByDevice(String from, String to) => {
        for (final r in db.select(
          'SELECT device, sum(seconds) AS seconds FROM screen_usage WHERE $_usageWhere GROUP BY device',
          [from, to],
        ))
          r['device'] as String: r['seconds'] as int,
      };

  /// Everything `todo usage` and the assistant need for a period, as JSON.
  Map<String, Object?> usageSummary(String from, String to) {
    final apps = usageByApp(from, to);
    final days = usageByDay(from, to);
    final total = days.values.fold(0, (a, b) => a + b);
    return {
      'from': from,
      'to': to,
      'total_seconds': total,
      'by_device': usageByDevice(from, to),
      'by_day': days,
      'apps': [for (final a in apps) a.toJson()],
      if (from == to) 'by_hour': usageByHour(from),
    };
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
      'screen_seconds': usageByDay(date, date)[date] ?? 0,
    };
  }
}
