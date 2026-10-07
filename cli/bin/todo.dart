import 'dart:convert';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:http/http.dart' as http;
import 'package:todo_cli/mcp.dart';
import 'package:todo_core/todo_core.dart';

final Store store = Store(openDb());

Future<void> main(List<String> args) async {
  final runner = CommandRunner<void>('todo', 'Tasks, habits and focus sessions.')
    ..argParser.addFlag('json', negatable: false, help: 'Print JSON instead of text.')
    ..addCommand(AddCommand())
    ..addCommand(ListCommand())
    ..addCommand(TodayCommand())
    ..addCommand(DoneCommand('done', 'Tick tasks.', true))
    ..addCommand(DoneCommand('undo', 'Untick tasks.', false))
    ..addCommand(EditCommand())
    ..addCommand(RmCommand())
    ..addCommand(ListsCommand())
    ..addCommand(HabitCommand())
    ..addCommand(FocusCommand())
    ..addCommand(UsageCommand())
    ..addCommand(_UsageAdd())
    ..addCommand(ServerCommand())
    ..addCommand(LoginCommand())
    ..addCommand(LogoutCommand())
    ..addCommand(SyncCommand())
    ..addCommand(McpCommand());
  try {
    await runner.run(args);
  } on UsageException catch (e) {
    stderr.writeln(e);
    exitCode = 64;
  } on FormatException catch (e) {
    stderr.writeln(e.message);
    exitCode = 64;
  } on TodoException catch (e) {
    stderr.writeln(e.message);
    exitCode = 1;
  } on SyncException catch (e) {
    stderr.writeln(e.message);
    exitCode = 1;
  } on SocketException {
    stderr.writeln('Offline: could not reach the sync server. Local changes are kept.');
    exitCode = 1;
  } on http.ClientException {
    stderr.writeln('Offline: could not reach the sync server. Local changes are kept.');
    exitCode = 1;
  }
}

abstract class Cmd extends Command<void> {
  Cmd(this.name, this.description);

  @override
  final String name;
  @override
  final String description;

  List<String> get rest => argResults!.rest;
  String? opt(String name) => argResults!.option(name);

  /// Prints [data] as JSON under `--json`, otherwise the lines from [text].
  void out(Object? data, String Function() text) =>
      print(globalResults!.flag('json') ? jsonEncode(data) : text());

  void needArgs(String what) {
    if (rest.isEmpty) usageException('Give $what.');
  }
}

String short(String id) => id.substring(0, 6);

String taskLine(Task t, {bool showDate = true}) {
  final time = t.startTime == null
      ? ''
      : t.endTime == null
          ? '${t.startTime} '
          : '${t.startTime}–${t.endTime} ';
  final date = showDate && t.date != null ? '${prettyDate(t.date!)} ' : '';
  final tag = t.tag == null ? '' : '  #${t.tag}';
  final list = t.list == null ? '' : '  (${t.list})';
  return '${t.done ? '[x]' : '[ ]'} ${short(t.id)}  $date$time${t.title}$tag$list';
}

String taskLines(List<Task> tasks, {bool showDate = true}) =>
    tasks.isEmpty ? 'No tasks.' : tasks.map((t) => taskLine(t, showDate: showDate)).join('\n');

String focusLine(FocusSession? s) {
  if (s == null) return 'No focus session running.';
  final left = s.plannedEnd.difference(DateTime.now());
  final on = s.taskTitle == null ? '' : ' on "${s.taskTitle}"';
  return '${s.kind == 'break' ? 'Break' : 'Focus'}$on: '
      '${left.inMinutes}:${(left.inSeconds % 60).toString().padLeft(2, '0')} left of ${s.plannedMin} min';
}

void addTaskOptions(Cmd c) {
  c.argParser
    ..addOption('date', abbr: 'd', help: 'today, tomorrow, fri, +3 or 2026-10-12.')
    ..addOption('time', abbr: 't', help: '17:30 or 17:30-18:15.')
    ..addOption('list', abbr: 'l', help: 'List name (created if new).')
    ..addOption('tag', help: 'Short label.')
    ..addOption('notes', abbr: 'n');
}

class AddCommand extends Cmd {
  AddCommand() : super('add', 'Add a task: todo add Buy milk -d tomorrow -t 18:00') {
    addTaskOptions(this);
  }

  @override
  void run() {
    needArgs('a title');
    final time = opt('time') == null ? null : parseTimeRange(opt('time')!);
    // A time without a date means today.
    final date = opt('date') != null
        ? parseDate(opt('date')!)
        : time != null
            ? today()
            : null;
    final t = store.addTask(
      title: rest.join(' '),
      listId: opt('list') == null ? null : store.ensureList(opt('list')!).id,
      date: date,
      startTime: time?.$1,
      endTime: time?.$2,
      tag: opt('tag'),
      notes: opt('notes'),
    );
    out(t.toJson(), () => 'Added ${taskLine(t)}');
  }
}

class ListCommand extends Cmd {
  ListCommand()
      : super('list', 'List tasks: todo list [today|tomorrow|week|overdue|all|undated|DATE]') {
    argParser
      ..addOption('list', abbr: 'l', help: 'Only this list.')
      ..addFlag('open', negatable: false, help: 'Hide ticked tasks.');
  }

  @override
  List<String> get aliases => ['ls'];

  @override
  void run() {
    final when = rest.isEmpty ? 'today' : rest.first.toLowerCase();
    String? listId;
    if (opt('list') != null) {
      final l = store.findList(opt('list')!);
      if (l == null) throw TodoException('No list called "${opt('list')}"');
      listId = l.id;
    }
    final includeDone = !argResults!.flag('open');
    final now = today();
    final tasks = switch (when) {
      'all' => store.tasks(undated: true, listId: listId, includeDone: includeDone),
      'undated' => store
          .tasks(undated: true, listId: listId, includeDone: includeDone)
          .where((t) => t.date == null)
          .toList(),
      'overdue' => store.tasks(overdueBefore: now, listId: listId),
      'week' => store.tasks(from: now, to: addDays(now, 6), listId: listId, includeDone: includeDone),
      _ => store.tasks(from: parseDate(when), to: parseDate(when), listId: listId, includeDone: includeDone),
    };
    out([for (final t in tasks) t.toJson()], () => taskLines(tasks));
  }
}

class TodayCommand extends Cmd {
  TodayCommand() : super('today', 'Tasks, habits and focus for today (or a given date).');

  @override
  void run() {
    final date = rest.isEmpty ? today() : parseDate(rest.first);
    final snap = store.snapshot(date);
    out(snap, () {
      final items = (snap['items'] as List).cast<Map<String, Object?>>();
      final done = items.where((i) => i['done'] == true).length;
      return [
        '${prettyDate(date)}: $done of ${items.length} done'
            '${snap['overdue'] == 0 ? '' : ', ${snap['overdue']} overdue'}',
        if (items.isEmpty) 'Nothing today.',
        for (final i in items)
          '${i['done'] == true ? '[x]' : '[ ]'} ${short(i['id'] as String)}  '
              '${(i['time'] as String? ?? '').padRight(5)}  ${i['title']}'
              '${i['kind'] == 'habit' ? '  (habit)' : ''}',
        '',
        '${focusLine(store.currentFocus())} ${snap['focused_min']} min focused today.',
      ].join('\n');
    });
  }
}

class DoneCommand extends Cmd {
  DoneCommand(super.name, super.description, this.done);

  final bool done;

  @override
  void run() {
    needArgs('one or more task ids');
    final ids = [for (final ref in rest) store.resolveId('tasks', ref)];
    final tasks = [for (final id in ids) store.setDone(id, done)];
    out([for (final t in tasks) t.toJson()], () => taskLines(tasks));
  }
}

class EditCommand extends Cmd {
  EditCommand() : super('edit', 'Change a task: todo edit ID -d fri -t 10:00. Use "none" to clear a field.') {
    argParser.addOption('title');
    addTaskOptions(this);
  }

  @override
  void run() {
    needArgs('a task id');
    final id = store.resolveId('tasks', rest.first);
    String? clearable(String v) => v.toLowerCase() == 'none' ? null : v;
    final changes = <String, Object?>{};
    if (opt('title') != null) changes['title'] = opt('title');
    if (opt('date') != null) {
      final v = clearable(opt('date')!);
      changes['date'] = v == null ? null : parseDate(v);
    }
    if (opt('time') != null) {
      final v = clearable(opt('time')!);
      final range = v == null ? null : parseTimeRange(v);
      changes['start_time'] = range?.$1;
      changes['end_time'] = range?.$2;
    }
    if (opt('list') != null) {
      final v = clearable(opt('list')!);
      changes['list_id'] = v == null ? null : store.ensureList(v).id;
    }
    if (opt('tag') != null) changes['tag'] = clearable(opt('tag')!);
    if (opt('notes') != null) changes['notes'] = clearable(opt('notes')!);
    if (changes.isEmpty) usageException('Nothing to change.');
    final t = store.updateTask(id, changes);
    out(t.toJson(), () => taskLine(t));
  }
}

class RmCommand extends Cmd {
  RmCommand() : super('rm', 'Delete tasks.');

  @override
  void run() {
    needArgs('one or more task ids');
    final ids = [for (final ref in rest) store.resolveId('tasks', ref)];
    final tasks = [for (final id in ids) store.task(id)];
    ids.forEach(store.deleteTask);
    out({'deleted': ids}, () => tasks.map((t) => 'Deleted ${short(t.id)}  ${t.title}').join('\n'));
  }
}

class ListsCommand extends Cmd {
  ListsCommand() : super('lists', 'Show lists; add one: todo lists add NAME; rename: todo lists rename OLD NEW');

  @override
  void run() {
    if (rest.length >= 2 && rest.first == 'add') store.ensureList(rest.skip(1).join(' '));
    if (rest.length == 3 && rest.first == 'rename') {
      final list = store.findList(rest[1]);
      if (list == null) throw TodoException('No list called "${rest[1]}"');
      store.renameList(list.id, rest[2]);
    }
    final lists = store.lists();
    out(
      [for (final l in lists) l.toJson()],
      () => lists.isEmpty ? 'No lists.' : lists.map((l) => '${short(l.id)}  ${l.title}').join('\n'),
    );
  }
}

class HabitCommand extends Cmd {
  HabitCommand() : super('habit', 'Daily habits.') {
    addSubcommand(_HabitList());
    addSubcommand(_HabitAdd());
    addSubcommand(_HabitCheck('check', 'Tick habits for a day: todo habit check ID... [-d DATE]', true));
    addSubcommand(_HabitCheck('uncheck', 'Untick habits for a day.', false));
    addSubcommand(_HabitTime());
    addSubcommand(_HabitRm());
  }

  @override
  void run() => _HabitList.show(this, today());
}

class _HabitList extends Cmd {
  _HabitList() : super('list', 'Habits for today or a given date.');

  static void show(Cmd c, String date) {
    final habits = store.habits(activeOn: date);
    final checked = store.checkedHabitIds(date);
    c.out(
      [
        for (final h in habits) {...h.toJson(), 'date': date, 'done': checked.contains(h.id)},
      ],
      () => habits.isEmpty
          ? 'No habits on ${prettyDate(date)}.'
          : habits
              .map((h) => '${checked.contains(h.id) ? '[x]' : '[ ]'} ${short(h.id)}  '
                  '${h.time == null ? '' : '${h.time} '}${h.title}')
              .join('\n'),
    );
  }

  @override
  void run() => show(this, rest.isEmpty ? today() : parseDate(rest.first));
}

class _HabitAdd extends Cmd {
  _HabitAdd() : super('add', 'Add a habit: todo habit add Read 20 min --from today --to 2026-12-29') {
    argParser
      ..addOption('time', abbr: 't', help: 'Time of day it sits at in the timeline, e.g. 07:00.')
      ..addOption('from', help: 'First day (default: no start).')
      ..addOption('to', help: 'Last day (default: no end).');
  }

  @override
  void run() {
    needArgs('a title');
    final h = store.addHabit(
      title: rest.join(' '),
      time: opt('time') == null ? null : parseTimeRange(opt('time')!).$1,
      startDate: opt('from') == null ? null : parseDate(opt('from')!),
      endDate: opt('to') == null ? null : parseDate(opt('to')!),
    );
    out(h.toJson(), () => 'Added habit ${short(h.id)}  ${h.title}');
  }
}

class _HabitCheck extends Cmd {
  _HabitCheck(super.name, super.description, this.done) {
    argParser.addOption('date', abbr: 'd', help: 'Day to mark (default today).');
  }

  final bool done;

  @override
  void run() {
    needArgs('one or more habit ids or exact titles');
    final date = opt('date') == null ? today() : parseDate(opt('date')!);
    for (final ref in rest) {
      store.setHabitCheck(store.resolveHabit(ref), date, done);
    }
    _HabitList.show(this, date);
  }
}

class _HabitTime extends Cmd {
  _HabitTime() : super('time', 'Set a habit\'s time of day: todo habit time ID 07:00 (or "none").');

  @override
  void run() {
    if (rest.length != 2) usageException('Give a habit id or exact title, then a time or "none".');
    final time = rest[1].toLowerCase() == 'none' ? null : parseTimeRange(rest[1]).$1;
    store.setHabitTime(store.resolveHabit(rest[0]), time);
    _HabitList.show(this, today());
  }
}

class _HabitRm extends Cmd {
  _HabitRm() : super('rm', 'Delete habits.');

  @override
  void run() {
    needArgs('one or more habit ids');
    final ids = [for (final ref in rest) store.resolveHabit(ref)];
    ids.forEach(store.deleteHabit);
    out({'deleted': ids}, () => 'Deleted ${ids.length} habit${ids.length == 1 ? '' : 's'}.');
  }
}

class FocusCommand extends Cmd {
  FocusCommand() : super('focus', 'Focus timer.') {
    addSubcommand(_FocusStart());
    addSubcommand(_FocusStop());
    addSubcommand(_FocusStatus());
  }

  @override
  void run() => _FocusStatus.show(this);
}

class _FocusStart extends Cmd {
  _FocusStart() : super('start', 'Start a session: todo focus start [TASK_ID] [-m 25] [--break]') {
    argParser
      ..addOption('minutes', abbr: 'm', help: 'Length (default 25, or 5 for a break).')
      ..addFlag('break', negatable: false, help: 'A break instead of a focus session.');
  }

  @override
  void run() {
    final isBreak = argResults!.flag('break');
    final minutes = int.tryParse(opt('minutes') ?? (isBreak ? '5' : '25'));
    if (minutes == null) usageException('Minutes must be a number.');
    final s = store.startFocus(
      taskId: rest.isEmpty ? null : store.resolveId('tasks', rest.first),
      minutes: minutes,
      kind: isBreak ? 'break' : 'focus',
    );
    out(s.toJson(), () => focusLine(s));
  }
}

class _FocusStop extends Cmd {
  _FocusStop() : super('stop', 'Stop the running session.');

  @override
  void run() {
    final s = store.stopFocus();
    out(
      s?.toJson(),
      () => s == null
          ? 'No focus session running.'
          : 'Stopped after ${s.endedAt!.difference(s.startedAt).inMinutes} min.',
    );
  }
}

class _FocusStatus extends Cmd {
  _FocusStatus() : super('status', 'Show the running session and minutes focused today.');

  static void show(Cmd c) {
    final s = store.currentFocus();
    final minutes = store.focusedMinutes(today());
    c.out(
      {'session': s?.toJson(), 'focused_min': minutes},
      () => '${focusLine(s)} $minutes min focused today.',
    );
  }

  @override
  void run() => show(this);
}

class UsageCommand extends Cmd {
  UsageCommand() : super('usage', 'Screen time: todo usage [today|yesterday|week|DATE]');

  @override
  void run() {
    final arg = rest.isEmpty ? 'today' : rest.first;
    final (from, to) = arg == 'week'
        ? (addDays(today(), -6), today())
        : (parseDate(arg), parseDate(arg));
    final s = store.usageSummary(from, to);
    out(s, () {
      final total = s['total_seconds'] as int;
      if (total == 0) return 'No screen time recorded.';
      final lines = [
        '${from == to ? prettyDate(from) : '${prettyDate(from)} – ${prettyDate(to)}'}: ${formatDuration(total)}',
        for (final e in (s['by_device'] as Map<String, int>).entries) '  ${e.key}: ${formatDuration(e.value)}',
        '',
      ];
      for (final a in (s['apps'] as List).cast<Map<String, Object?>>().take(15)) {
        lines.add('${formatDuration(a['seconds'] as int).padLeft(7)}  ${a['name']}');
      }
      if (from != to) {
        lines.add('');
        for (final e in (s['by_day'] as Map<String, int>).entries) {
          lines.add('${prettyDate(e.key)}  ${formatDuration(e.value)}');
        }
      } else {
        final hours = s['by_hour'] as List<int>;
        final peak = hours.reduce((a, b) => a > b ? a : b);
        lines.add('');
        for (var h = 0; h < 24; h++) {
          if (hours[h] == 0) continue;
          lines.add('${h.toString().padLeft(2, '0')}:00  ${'█' * (hours[h] * 30 ~/ peak).clamp(1, 30)} ${formatDuration(hours[h])}');
        }
      }
      return lines.join('\n');
    });
  }
}

/// Used by the GNOME extension to report which window had focus.
class _UsageAdd extends Cmd {
  @override
  bool get hidden => true;

  _UsageAdd() : super('usage-add', 'Record foreground time: todo usage-add \'[{"app":..,"name":..,"start":ISO,"end":ISO}]\'');

  @override
  void run() {
    needArgs('a JSON list of spans');
    final spans = [
      for (final s in jsonDecode(rest.first) as List)
        UsageSpan(
          s['app'] as String,
          s['name'] as String,
          DateTime.parse(s['start'] as String).toLocal(),
          DateTime.parse(s['end'] as String).toLocal(),
        ),
    ];
    if (store.getMeta('device_name') == null) store.setDeviceName(Platform.localHostname);
    store.addUsage(spans);
    out({'recorded': spans.length}, () => 'Recorded ${spans.length} spans.');
  }
}

class McpCommand extends Cmd {
  McpCommand() : super('mcp', 'Run the MCP server on stdin/stdout (for Claude).');

  @override
  Future<void> run() => serveMcp(store);
}

String prompt(String label, {bool secret = false}) {
  stderr.write('$label: ');
  if (!secret || !stdin.hasTerminal) return stdin.readLineSync()?.trim() ?? '';
  stdin.echoMode = false;
  try {
    return stdin.readLineSync() ?? '';
  } finally {
    stdin.echoMode = true;
    stderr.writeln();
  }
}

class LoginCommand extends Cmd {
  LoginCommand() : super('login', 'Sign in to the sync server (set it first with: todo server).') {
    argParser.addOption('email');
  }

  @override
  Future<void> run() async {
    final remote = SupabaseRemote(store);
    final email = opt('email') ?? prompt('Email');
    await remote.signIn(email, prompt('Password', secret: true));
    final r = await SyncEngine(store, remote).sync();
    out({'email': email, ...r.toJson()}, () => 'Signed in as $email. Pulled ${r.pulled}, pushed ${r.pushed}.');
  }
}

class ServerCommand extends Cmd {
  ServerCommand() : super('server', 'Show the sync server, or set it: todo server URL PUBLISHABLE_KEY');

  @override
  void run() {
    final remote = SupabaseRemote(store);
    if (rest.length == 2) {
      remote.configure(url: rest[0], anonKey: rest[1]);
    } else if (rest.isNotEmpty) {
      usageException('Give the project URL and its publishable key, or nothing to show the current server.');
    }
    out(
      {'url': remote.url, 'signed_in': remote.signedIn, 'email': remote.email},
      () => remote.url == null
          ? 'No sync server set.'
          : '${remote.url}  (${remote.signedIn ? 'signed in as ${remote.email}' : 'not signed in'})',
    );
  }
}

class LogoutCommand extends Cmd {
  LogoutCommand() : super('logout', 'Sign out of sync on this device. Local data stays.');

  @override
  void run() {
    SupabaseRemote(store).signOut();
    out({'signed_in': false}, () => 'Signed out.');
  }
}

class SyncCommand extends Cmd {
  SyncCommand() : super('sync', 'Sync with the server now.');

  @override
  Future<void> run() async {
    final r = await SyncEngine(store, SupabaseRemote(store)).sync();
    out(r.toJson(), () => 'Pulled ${r.pulled}, pushed ${r.pushed}.');
  }
}
