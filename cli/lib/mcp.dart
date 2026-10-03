import 'dart:convert';
import 'dart:io';

import 'package:todo_core/todo_core.dart';

typedef _Handler = Object? Function(Store store, Map<String, Object?> args);

class _Tool {
  const _Tool(this.name, this.description, this.properties, this.handler, {this.required = const []});

  final String name;
  final String description;
  final Map<String, Object?> properties;
  final List<String> required;
  final _Handler handler;

  Map<String, Object?> toJson() => {
        'name': name,
        'description': description,
        'inputSchema': {'type': 'object', 'properties': properties, 'required': required},
      };
}

Map<String, Object?> _str(String description) => {'type': 'string', 'description': description};

const _dateHelp = 'today, tomorrow, a weekday, +N days, or YYYY-MM-DD';

final _taskFields = {
  'date': _str('When it is due: $_dateHelp.'),
  'time': _str('Start time or range in 24h local time: 17:30 or 17:30-18:15.'),
  'list': _str('List name; created if it does not exist.'),
  'tag': _str('Short label, e.g. Exam prep.'),
  'notes': _str('Free-text notes.'),
};

String? _s(Map<String, Object?> a, String key) => a[key] as String?;

String _taskId(Store store, Map<String, Object?> a) => store.resolveId('tasks', a['id'] as String);

final _tools = <_Tool>[
  _Tool(
    'today',
    'One day: `items` is the timeline of tasks and habits in time order; also the running focus session and minutes focused.',
    {'date': _str('Day to show ($_dateHelp). Defaults to today.')},
    (store, a) => store.snapshot(_s(a, 'date') == null ? null : parseDate(_s(a, 'date')!)),
  ),
  _Tool(
    'list_tasks',
    'List tasks in a date range, or overdue, or everything.',
    {
      'from': _str('First day ($_dateHelp).'),
      'to': _str('Last day ($_dateHelp).'),
      'overdue': {'type': 'boolean', 'description': 'Only open tasks dated before today.'},
      'include_undated': {'type': 'boolean', 'description': 'Also return tasks with no date.'},
      'open_only': {'type': 'boolean', 'description': 'Hide completed tasks.'},
      'list': _str('Only tasks in this list.'),
    },
    (store, a) {
      String? listId;
      if (_s(a, 'list') != null) {
        final l = store.findList(_s(a, 'list')!);
        if (l == null) throw TodoException('No list called "${_s(a, 'list')}"');
        listId = l.id;
      }
      final tasks = store.tasks(
        from: _s(a, 'from') == null ? null : parseDate(_s(a, 'from')!),
        to: _s(a, 'to') == null ? null : parseDate(_s(a, 'to')!),
        overdueBefore: a['overdue'] == true ? today() : null,
        undated: a['include_undated'] == true,
        includeDone: a['open_only'] != true,
        listId: listId,
      );
      return [for (final t in tasks) t.toJson()];
    },
  ),
  _Tool(
    'add_task',
    'Add a task.',
    {'title': _str('What to do.'), ..._taskFields},
    required: ['title'],
    (store, a) {
      final time = _s(a, 'time') == null ? null : parseTimeRange(_s(a, 'time')!);
      final date = _s(a, 'date') != null
          ? parseDate(_s(a, 'date')!)
          : time != null
              ? today()
              : null;
      return store
          .addTask(
            title: a['title'] as String,
            listId: _s(a, 'list') == null ? null : store.ensureList(_s(a, 'list')!).id,
            date: date,
            startTime: time?.$1,
            endTime: time?.$2,
            tag: _s(a, 'tag'),
            notes: _s(a, 'notes'),
          )
          .toJson();
    },
  ),
  _Tool(
    'update_task',
    'Change fields of a task. Pass "none" to clear date, time, list, tag or notes.',
    {'id': _str('Task id or unique prefix.'), 'title': _str('New title.'), ..._taskFields},
    required: ['id'],
    (store, a) {
      String? clearable(String v) => v.toLowerCase() == 'none' ? null : v;
      final changes = <String, Object?>{};
      if (_s(a, 'title') != null) changes['title'] = _s(a, 'title');
      if (_s(a, 'date') != null) {
        final v = clearable(_s(a, 'date')!);
        changes['date'] = v == null ? null : parseDate(v);
      }
      if (_s(a, 'time') != null) {
        final v = clearable(_s(a, 'time')!);
        final range = v == null ? null : parseTimeRange(v);
        changes['start_time'] = range?.$1;
        changes['end_time'] = range?.$2;
      }
      if (_s(a, 'list') != null) {
        final v = clearable(_s(a, 'list')!);
        changes['list_id'] = v == null ? null : store.ensureList(v).id;
      }
      if (_s(a, 'tag') != null) changes['tag'] = clearable(_s(a, 'tag')!);
      if (_s(a, 'notes') != null) changes['notes'] = clearable(_s(a, 'notes')!);
      return store.updateTask(_taskId(store, a), changes).toJson();
    },
  ),
  _Tool(
    'set_task_done',
    'Tick or untick a task.',
    {
      'id': _str('Task id or unique prefix.'),
      'done': {'type': 'boolean', 'description': 'Defaults to true.'},
    },
    required: ['id'],
    (store, a) => store.setDone(_taskId(store, a), a['done'] != false).toJson(),
  ),
  _Tool(
    'delete_task',
    'Delete a task.',
    {'id': _str('Task id or unique prefix.')},
    required: ['id'],
    (store, a) {
      final id = _taskId(store, a);
      store.deleteTask(id);
      return {'deleted': id};
    },
  ),
  _Tool(
    'add_habit',
    'Add a daily habit, optionally limited to a date range.',
    {'title': _str('The habit.'), 'time': _str('Time of day it sits at in the timeline, e.g. 07:00.'), 'from': _str('First day ($_dateHelp).'), 'to': _str('Last day ($_dateHelp).')},
    required: ['title'],
    (store, a) => store
        .addHabit(
          title: a['title'] as String,
          time: _s(a, 'time') == null ? null : parseTimeRange(_s(a, 'time')!).$1,
          startDate: _s(a, 'from') == null ? null : parseDate(_s(a, 'from')!),
          endDate: _s(a, 'to') == null ? null : parseDate(_s(a, 'to')!),
        )
        .toJson(),
  ),
  _Tool(
    'set_habit_done',
    'Tick or untick a habit for one day. Habits and their state are listed by the today tool.',
    {
      'habit': _str('Habit id, unique id prefix, or exact title.'),
      'date': _str('Day ($_dateHelp). Defaults to today.'),
      'done': {'type': 'boolean', 'description': 'Defaults to true.'},
    },
    required: ['habit'],
    (store, a) {
      final id = store.resolveHabit(a['habit'] as String);
      final date = _s(a, 'date') == null ? today() : parseDate(_s(a, 'date')!);
      store.setHabitCheck(id, date, a['done'] != false);
      return {'habit_id': id, 'date': date, 'done': a['done'] != false};
    },
  ),
  _Tool(
    'focus_start',
    'Start a focus (or break) timer, optionally on a task. Replaces any running session.',
    {
      'task_id': _str('Task id or unique prefix.'),
      'minutes': {'type': 'integer', 'description': 'Length; default 25, or 5 for a break.'},
      'break': {'type': 'boolean', 'description': 'A break rather than a focus session.'},
    },
    (store, a) {
      final isBreak = a['break'] == true;
      return store
          .startFocus(
            taskId: _s(a, 'task_id') == null ? null : store.resolveId('tasks', _s(a, 'task_id')!),
            minutes: (a['minutes'] as num?)?.toInt() ?? (isBreak ? 5 : 25),
            kind: isBreak ? 'break' : 'focus',
          )
          .toJson();
    },
  ),
  _Tool(
    'focus_stop',
    'Stop the running focus session.',
    {},
    (store, a) => store.stopFocus()?.toJson() ?? {'stopped': false, 'reason': 'No session running'},
  ),
];

/// Minimal MCP server: newline-delimited JSON-RPC on stdin/stdout.
Future<void> serveMcp(Store store) async {
  void send(Object? id, {Object? result, Map<String, Object?>? error}) {
    stdout.writeln(jsonEncode({
      'jsonrpc': '2.0',
      'id': id,
      if (error != null) 'error': error else 'result': result,
    }));
  }

  await for (final line in stdin.transform(utf8.decoder).transform(const LineSplitter())) {
    if (line.trim().isEmpty) continue;
    final Map<String, Object?> msg;
    try {
      msg = jsonDecode(line) as Map<String, Object?>;
    } catch (_) {
      send(null, error: {'code': -32700, 'message': 'Parse error'});
      continue;
    }
    final id = msg['id'];
    final params = (msg['params'] as Map<String, Object?>?) ?? {};
    // Notifications carry no id and get no reply.
    if (!msg.containsKey('id')) continue;

    switch (msg['method']) {
      case 'initialize':
        send(id, result: {
          'protocolVersion': params['protocolVersion'] ?? '2025-06-18',
          'capabilities': {'tools': <String, Object?>{}},
          'serverInfo': {'name': 'todo', 'version': '0.1.0'},
        });
      case 'ping':
        send(id, result: <String, Object?>{});
      case 'tools/list':
        send(id, result: {'tools': [for (final t in _tools) t.toJson()]});
      case 'tools/call':
        final tool = _tools.where((t) => t.name == params['name']).firstOrNull;
        if (tool == null) {
          send(id, error: {'code': -32602, 'message': 'Unknown tool: ${params['name']}'});
          break;
        }
        String text;
        var isError = false;
        try {
          final args = (params['arguments'] as Map<String, Object?>?) ?? {};
          text = jsonEncode(tool.handler(store, args));
        } on TodoException catch (e) {
          text = e.message;
          isError = true;
        } on FormatException catch (e) {
          text = e.message;
          isError = true;
        } on TypeError {
          text = 'Wrong argument type for ${tool.name}';
          isError = true;
        }
        send(id, result: {
          'content': [
            {'type': 'text', 'text': text},
          ],
          'isError': isError,
        });
      default:
        send(id, error: {'code': -32601, 'message': 'Method not found: ${msg['method']}'});
    }
  }
}
