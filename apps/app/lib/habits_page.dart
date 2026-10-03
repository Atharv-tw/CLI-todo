import 'package:flutter/material.dart';
import 'package:todo_core/todo_core.dart';

import 'heatmap.dart';
import 'state.dart';
import 'theme.dart';

String _days(int n) => '$n ${n == 1 ? 'day' : 'days'}';

/// Habits only: a streak summary, then one tile per habit to tap done.
class HabitsPage extends StatelessWidget {
  const HabitsPage({super.key});

  Future<void> _add(BuildContext context) async {
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
    if (title != null && title.trim().isNotEmpty && context.mounted) {
      AppScope.of(context).change((s) => s.addHabit(title: title, startDate: today()));
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final text = Theme.of(context).textTheme;
    final now = today();
    final active = app.store.habits(activeOn: now);
    final upcoming = app.store
        .habits()
        .where((h) => h.startDate != null && h.startDate!.compareTo(now) > 0)
        .toList();
    final checked = app.store.checkedHabitIds(now);
    final doneToday = active.where((h) => checked.contains(h.id)).length;
    final streak = app.store.overallStreak(now, false);

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('All habits', style: text.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                Text(
                  'A day counts once at least one habit is done',
                  style: text.bodySmall?.copyWith(color: AppColors.muted),
                ),
                const SizedBox(height: 12),
                Row(
                  spacing: 8,
                  children: [
                    Expanded(child: StatTile(_days(streak.current), 'Current streak')),
                    Expanded(child: StatTile(_days(streak.best), 'Best streak')),
                    Expanded(child: StatTile('$doneToday of ${active.length}', 'Done today')),
                  ],
                ),
              ],
            ),
          ),
        ),
        if (active.isEmpty && upcoming.isEmpty)
          const Padding(
            padding: EdgeInsets.only(top: 32),
            child: Center(child: Text('No habits yet.', style: TextStyle(color: AppColors.muted))),
          ),
        for (final h in active) ...[
          const SizedBox(height: 10),
          _HabitTile(habit: h, done: checked.contains(h.id)),
        ],
        if (upcoming.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 20, 4, 0),
            child: Text('Not started yet', style: text.titleSmall?.copyWith(color: AppColors.muted)),
          ),
        for (final h in upcoming) ...[
          const SizedBox(height: 10),
          _HabitTile(habit: h, done: false, startsLater: true),
        ],
        const SizedBox(height: 16),
        Center(
          child: FilledButton.icon(
            icon: const Icon(Icons.add),
            label: const Text('New habit'),
            onPressed: () => _add(context),
          ),
        ),
      ],
    );
  }
}

/// Tap to mark today done or not done.
class _HabitTile extends StatelessWidget {
  const _HabitTile({required this.habit, required this.done, this.startsLater = false});

  final Habit habit;
  final bool done;
  final bool startsLater;

  Future<void> _setTime(BuildContext context, AppState app) async {
    final parts = (habit.time ?? '09:00').split(':').map(int.parse).toList();
    final picked = await showTimePicker(
      context: context,
      helpText: 'Time of day for "${habit.title}"',
      initialTime: TimeOfDay(hour: parts[0], minute: parts[1]),
    );
    if (picked != null) {
      app.change((s) => s.setHabitTime(habit.id, hm(DateTime(2000, 1, 1, picked.hour, picked.minute))));
    }
  }

  Future<void> _delete(BuildContext context, AppState app) async {
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
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final text = Theme.of(context).textTheme;
    final now = today();
    final streak = app.store.habitStreak(habit.id, now);

    // Share of days done since the habit began (or the last 30 days).
    final thirtyAgo = addDays(now, -29);
    final from = habit.startDate != null && habit.startDate!.compareTo(thirtyAgo) > 0 ? habit.startDate! : thirtyAgo;
    final span = startsLater ? 0 : parseYmd(now).difference(parseYmd(from)).inDays + 1;
    final hits = startsLater ? 0 : app.store.habitDays(habit.id, from, now).length;

    final stats = startsLater
        ? 'Starts ${prettyDate(habit.startDate!)}'
        : [
            ?habit.time,
            '${streak.current}-day streak',
            '$hits of last $span days',
          ].join(' · ');

    return Card(
      color: done ? AppColors.green.withValues(alpha: 0.16) : null,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        key: ValueKey('habit-${habit.id}'),
        onTap: startsLater ? null : () => app.change((s) => s.setHabitCheck(habit.id, now, !done)),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 4, 12),
          child: Row(
            spacing: 14,
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: done ? AppColors.green : Colors.transparent,
                  border: done ? null : Border.all(color: startsLater ? AppColors.line : AppColors.muted, width: 2),
                ),
                child: done ? const Icon(Icons.check_rounded, size: 22, color: AppColors.onLight) : null,
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      habit.title,
                      style: text.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: startsLater ? AppColors.muted : null,
                      ),
                    ),
                    Text(stats, style: text.bodySmall?.copyWith(color: AppColors.muted)),
                  ],
                ),
              ),
              PopupMenuButton<String>(
                tooltip: 'More',
                icon: const Icon(Icons.more_vert, color: AppColors.muted),
                onSelected: (v) => v == 'time' ? _setTime(context, app) : _delete(context, app),
                itemBuilder: (context) => const [
                  PopupMenuItem(value: 'time', child: Text('Set time of day')),
                  PopupMenuItem(value: 'delete', child: Text('Delete')),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
