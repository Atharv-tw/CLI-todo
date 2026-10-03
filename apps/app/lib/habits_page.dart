import 'package:flutter/material.dart';
import 'package:todo_core/todo_core.dart';

import 'heatmap.dart';
import 'state.dart';
import 'theme.dart';

const _monthNames = [
  'January', 'February', 'March', 'April', 'May', 'June',
  'July', 'August', 'September', 'October', 'November', 'December',
];

/// Month streak grids: one for everything, then one per habit.
class HabitsPage extends StatefulWidget {
  const HabitsPage({super.key});

  @override
  State<HabitsPage> createState() => _HabitsPageState();
}

class _HabitsPageState extends State<HabitsPage> {
  /// Months back from the current one; 0 is this month.
  int _back = 0;

  Future<void> _add() async {
    final controller = TextEditingController();
    final title = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('New daily habit'),
        content: TextField(
          controller: controller,
          autofocus: true,
          textCapitalization: TextCapitalization.sentences,
          onSubmitted: (v) => Navigator.pop(context, v),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, controller.text), child: const Text('Add')),
        ],
      ),
    );
    if (title != null && title.trim().isNotEmpty && mounted) {
      AppScope.of(context).change((s) => s.addHabit(title: title, startDate: today()));
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final text = Theme.of(context).textTheme;
    final nowDate = DateTime.now();
    final now = today(nowDate);
    final month = DateTime(nowDate.year, nowDate.month - _back, 1);
    final from = ymd(month);
    final to = ymd(DateTime(month.year, month.month + 1, 0));
    // Stats cover the month up to today, not days that have not happened yet.
    final upTo = to.compareTo(now) < 0 ? to : now;

    final completion = app.store.dayCompletion(from, to);
    final overall = app.store.overallStreak(now);
    var doneSum = 0, totalSum = 0;
    for (final e in completion.entries) {
      if (e.key.compareTo(upTo) > 0) continue;
      doneSum += e.value.done;
      totalSum += e.value.total;
    }
    final habits = app.store.habits();

    return Scaffold(
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        children: [
          Row(
            children: [
              IconButton(
                tooltip: 'Previous month',
                icon: const Icon(Icons.chevron_left),
                onPressed: () => setState(() => _back++),
              ),
              Expanded(
                child: Text(
                  '${_monthNames[month.month - 1]} ${month.year}',
                  textAlign: TextAlign.center,
                  style: text.titleSmall,
                ),
              ),
              IconButton(
                tooltip: 'Next month',
                icon: const Icon(Icons.chevron_right),
                onPressed: _back == 0 ? null : () => setState(() => _back--),
              ),
            ],
          ),
          const SizedBox(height: 4),
          _StreakCard(
            title: 'Everything',
            subtitle: 'Tasks and habits completed each day',
            heatmap: MonthHeatmap(
              month: month,
              value: (d) {
                final c = completion[d]!;
                return c.total == 0 ? 0 : c.done / c.total;
              },
            ),
            stats: [
              StatTile('${overall.current} ${overall.current == 1 ? 'day' : 'days'}', 'Current streak'),
              StatTile('${overall.best} ${overall.best == 1 ? 'day' : 'days'}', 'Best streak'),
              StatTile('${totalSum == 0 ? 0 : (doneSum * 100 / totalSum).round()}%', 'Done this month'),
            ],
          ),
          if (habits.isEmpty)
            const Padding(
              padding: EdgeInsets.only(top: 32),
              child: Center(child: Text('No habits yet.', style: TextStyle(color: AppColors.muted))),
            ),
          for (final h in habits) ...[
            const SizedBox(height: 12),
            _HabitCard(habit: h, month: month, from: from, upTo: upTo, now: now),
          ],
          const SizedBox(height: 16),
          Center(
            child: FilledButton.icon(
              icon: const Icon(Icons.add),
              label: const Text('New habit'),
              onPressed: _add,
            ),
          ),
        ],
      ),
    );
  }
}

class _StreakCard extends StatelessWidget {
  const _StreakCard({
    required this.title,
    required this.subtitle,
    required this.heatmap,
    required this.stats,
    this.trailing,
    this.footer,
  });

  final String title;
  final String subtitle;
  final Widget heatmap;
  final List<Widget> stats;
  final Widget? trailing;
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: text.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                      Text(subtitle, style: text.bodySmall?.copyWith(color: AppColors.muted)),
                    ],
                  ),
                ),
                ?trailing,
              ],
            ),
            const SizedBox(height: 14),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: 14,
              children: [
                heatmap,
                Expanded(child: Column(spacing: 8, children: [...stats, ?footer])),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _HabitCard extends StatelessWidget {
  const _HabitCard({
    required this.habit,
    required this.month,
    required this.from,
    required this.upTo,
    required this.now,
  });

  final Habit habit;
  final DateTime month;
  final String from, upTo, now;

  bool _active(String date) =>
      (habit.startDate == null || habit.startDate!.compareTo(date) <= 0) &&
      (habit.endDate == null || habit.endDate!.compareTo(date) >= 0);

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final to = ymd(DateTime(month.year, month.month + 1, 0));
    final days = app.store.habitDays(habit.id, from, to);
    final streak = app.store.habitStreak(habit.id, now);
    var due = 0;
    for (var d = from; d.compareTo(upTo) <= 0; d = addDays(d, 1)) {
      if (_active(d)) due++;
    }
    final doneToday = app.store.checkedHabitIds(now).contains(habit.id);
    final activeToday = _active(now);

    void toggle(String date) => app.change((s) => s.setHabitCheck(habit.id, date, !days.contains(date)));

    return _StreakCard(
      title: habit.title,
      subtitle: [
        ?habit.time,
        if (!activeToday) (habit.startDate != null && habit.startDate!.compareTo(now) > 0)
            ? 'Starts ${prettyDate(habit.startDate!)}'
            : 'Ended',
        if (activeToday) 'Every day',
      ].join(' · '),
      trailing: IconButton(
        tooltip: 'Delete habit',
        icon: const Icon(Icons.delete_outline, color: AppColors.muted),
        onPressed: () async {
          final ok = await showDialog<bool>(
            context: context,
            builder: (context) => AlertDialog(
              title: Text('Delete "${habit.title}"?'),
              content: const Text('Its history goes with it.'),
              actions: [
                TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
                FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Delete')),
              ],
            ),
          );
          if (ok == true) app.change((s) => s.deleteHabit(habit.id));
        },
      ),
      heatmap: MonthHeatmap(
        month: month,
        keyPrefix: 'heat-${habit.id}',
        value: (d) => !_active(d) ? null : (days.contains(d) ? 1 : 0),
        onTap: toggle,
      ),
      stats: [
        StatTile('${streak.current} ${streak.current == 1 ? 'day' : 'days'}', 'Current streak'),
        if (due == 0)
          const StatTile('–', 'Not started this month')
        else
          StatTile(
            '${days.length} of $due',
            'Days done · ${(days.where((d) => d.compareTo(upTo) <= 0).length * 100 / due).round()}%',
          ),
      ],
      footer: !activeToday
          ? null
          : SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                key: ValueKey('done-${habit.id}'),
                style: FilledButton.styleFrom(
                  backgroundColor: doneToday ? AppColors.raised : AppColors.green,
                  foregroundColor: doneToday ? AppColors.ink : AppColors.onLight,
                ),
                icon: Icon(doneToday ? Icons.undo : Icons.check_circle, size: 18),
                label: Text(doneToday ? 'Undo today' : 'Done today'),
                onPressed: () => app.change((s) => s.setHabitCheck(habit.id, now, !doneToday)),
              ),
            ),
    );
  }
}
