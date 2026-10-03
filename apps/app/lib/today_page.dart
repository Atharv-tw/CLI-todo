import 'dart:async';

import 'package:flutter/material.dart';
import 'package:todo_core/todo_core.dart';

import 'heatmap.dart';
import 'state.dart';
import 'task_widgets.dart';
import 'theme.dart';
import 'timeline.dart';

class TodayPage extends StatefulWidget {
  const TodayPage({super.key});

  @override
  State<TodayPage> createState() => _TodayPageState();
}

class _TodayPageState extends State<TodayPage> {
  /// Null means "today", so the page rolls over at midnight on its own.
  String? _picked;

  // Keeps the "now" marker and the date current while the page sits open.
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
    final text = Theme.of(context).textTheme;
    final now = today();
    final date = _picked ?? now;
    final tasks = {for (final t in app.store.tasks(from: date, to: date)) t.id: t};
    final items = (app.store.snapshot(date)['items'] as List).cast<Map<String, Object?>>();
    final overdue = date == now ? app.store.tasks(overdueBefore: now) : const <Task>[];
    final done = items.where((i) => i['done'] == true).length;

    return Scaffold(
      floatingActionButton: FloatingActionButton(
        tooltip: 'Add task',
        shape: const CircleBorder(),
        onPressed: () => showTaskSheet(context, date: date),
        child: const Icon(Icons.add),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 96),
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
                    date == now ? 'Today, ${prettyDate(date)}' : '${prettyDate(date)}  ·  back to today',
                    style: text.titleSmall?.copyWith(color: AppColors.ink),
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
          const SizedBox(height: 4),
          _ActivityCard(selected: date, onPick: (d) => setState(() => _picked = d == now ? null : d)),
          const SizedBox(height: 12),
          _ProgressCard(done: done, total: items.length, overdue: overdue.length),
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 24, 4, 4),
            child: Text(
              date == now ? "Today's timeline" : 'Timeline',
              style: text.titleLarge?.copyWith(fontWeight: FontWeight.w700),
            ),
          ),
          if (items.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Center(child: Text('Nothing scheduled', style: TextStyle(color: AppColors.muted))),
            ),
          for (final (index, i) in items.indexed)
            TimelineRow(
              item: i,
              date: date,
              first: index == 0,
              last: index == items.length - 1,
              task: tasks[i['id']],
            ),
          if (overdue.isNotEmpty)
            ExpansionTile(
              tilePadding: const EdgeInsets.symmetric(horizontal: 4),
              shape: const Border(),
              title: Text(
                '${overdue.length} overdue',
                style: const TextStyle(color: AppColors.red, fontWeight: FontWeight.w600),
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

/// GitHub-style calendar of how much was done each day, tasks and habits
/// together. Tapping a day opens it.
class _ActivityCard extends StatelessWidget {
  const _ActivityCard({required this.selected, required this.onPick});

  final String selected;
  final void Function(String date) onPick;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final text = Theme.of(context).textTheme;
    final now = today();
    final completion = app.store.dayCompletion(addDays(now, -53 * 7), now);
    final streak = app.store.overallStreak(now);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text('Activity', style: text.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                ),
                Text(
                  '${streak.current}-day streak · best ${streak.best}',
                  style: text.bodySmall?.copyWith(color: AppColors.muted),
                ),
              ],
            ),
            const SizedBox(height: 12),
            ActivityCalendar(
              selected: selected,
              onTap: onPick,
              value: (d) {
                final c = completion[d];
                return c == null || c.total == 0 ? 0 : c.done / c.total;
              },
            ),
          ],
        ),
      ),
    );
  }
}

/// Cream card: how much of the day is done, with a ring.
class _ProgressCard extends StatelessWidget {
  const _ProgressCard({required this.done, required this.total, required this.overdue});

  final int done, total, overdue;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final fraction = total == 0 ? 0.0 : done / total;
    const dark = AppColors.onLight;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: AppColors.cream, borderRadius: BorderRadius.circular(cardRadius)),
      child: Row(
        spacing: 14,
        children: [
          const CircleAvatar(
            radius: 24,
            backgroundColor: AppColors.orange,
            child: Icon(Icons.check_rounded, color: Colors.white),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  total == 0 ? 'Nothing scheduled' : '$done of $total done',
                  style: text.titleLarge?.copyWith(color: dark, fontWeight: FontWeight.w700),
                ),
                Text(
                  overdue > 0 ? '$overdue overdue' : 'Nothing overdue',
                  style: text.bodySmall?.copyWith(
                    color: overdue > 0 ? const Color(0xFFB3261E) : dark.withValues(alpha: 0.6),
                    fontWeight: overdue > 0 ? FontWeight.w600 : null,
                  ),
                ),
              ],
            ),
          ),
          SizedBox.square(
            dimension: 52,
            child: Stack(
              fit: StackFit.expand,
              children: [
                CircularProgressIndicator(
                  value: fraction,
                  strokeWidth: 5,
                  strokeCap: StrokeCap.round,
                  color: AppColors.orange,
                  backgroundColor: dark.withValues(alpha: 0.12),
                ),
                Center(
                  child: Text(
                    '${(fraction * 100).round()}%',
                    style: text.labelMedium?.copyWith(color: dark, fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
