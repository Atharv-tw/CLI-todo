import 'dart:async';

import 'package:flutter/material.dart';
import 'package:todo_core/todo_core.dart';

import 'state.dart';
import 'task_widgets.dart';

class TodayPage extends StatefulWidget {
  const TodayPage({super.key});

  @override
  State<TodayPage> createState() => _TodayPageState();
}

class _TodayPageState extends State<TodayPage> {
  /// Null means "today", so the page rolls over at midnight on its own.
  String? _picked;

  // Keeps the "now" block and the date current while the page sits open.
  late final Timer _tick = Timer.periodic(const Duration(seconds: 20), (_) => setState(() {}));

  @override
  void initState() {
    super.initState();
    _tick;
  }

  @override
  void dispose() {
    _tick.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final theme = Theme.of(context);
    final now = today();
    final date = _picked ?? now;
    final tasks = {for (final t in app.store.tasks(from: date, to: date)) t.id: t};
    final items = (app.store.snapshot(date)['items'] as List).cast<Map<String, Object?>>();
    final overdue = date == now ? app.store.tasks(overdueBefore: now) : const <Task>[];
    final done = items.where((i) => i['done'] == true).length;

    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        icon: const Icon(Icons.add),
        label: const Text('Task'),
        onPressed: () => showTaskSheet(context, date: date),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
        children: [
          Row(
            children: [
              IconButton(
                tooltip: 'Previous day',
                icon: const Icon(Icons.chevron_left),
                onPressed: () => setState(() => _picked = addDays(date, -1)),
              ),
              Expanded(
                child: TextButton(
                  onPressed: date == now ? null : () => setState(() => _picked = null),
                  child: Text(
                    date == now ? 'Today, ${prettyDate(date)}' : '${prettyDate(date)}  (back to today)',
                    style: theme.textTheme.titleMedium,
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Next day',
                icon: const Icon(Icons.chevron_right),
                onPressed: () => setState(() => _picked = addDays(date, 1)),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(99),
            child: LinearProgressIndicator(
              minHeight: 8,
              value: items.isEmpty ? 0 : done / items.length,
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(
              items.isEmpty ? 'Nothing scheduled' : '$done of ${items.length} done',
              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ),
          for (final i in items) ...[
            if (i['kind'] == 'task')
              TaskTile(tasks[i['id']]!)
            else
              HabitTile(
                id: i['id'] as String,
                title: i['title'] as String,
                time: i['time'] as String?,
                done: i['done'] == true,
                date: date,
              ),
            const SizedBox(height: 8),
          ],
          if (overdue.isNotEmpty)
            ExpansionTile(
              tilePadding: const EdgeInsets.symmetric(horizontal: 4),
              shape: const Border(),
              title: Text(
                '${overdue.length} overdue',
                style: TextStyle(color: theme.colorScheme.error, fontWeight: FontWeight.w600),
              ),
              children: [
                for (final t in overdue) ...[TaskTile(t, showDate: true), const SizedBox(height: 8)],
              ],
            ),
        ],
      ),
    );
  }
}
