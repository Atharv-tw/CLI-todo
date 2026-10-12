import 'package:flutter/material.dart';
import 'package:todo_core/todo_core.dart';

import 'heatmap.dart';
import 'state.dart';
import 'theme.dart';

String _days(int n) => '$n ${n == 1 ? 'day' : 'days'}';

String _hm(TimeOfDay t) => hm(DateTime(2000, 1, 1, t.hour, t.minute));

typedef _NewHabit = ({String title, List<({String name, String? time})> steps});

/// Name a habit and, optionally, split it into steps through the day (five
/// meals, four litres of water): each step reminds at its own time and the
/// habit is done once all are ticked.
class _NewHabitDialog extends StatefulWidget {
  const _NewHabitDialog();

  @override
  State<_NewHabitDialog> createState() => _NewHabitDialogState();
}

class _NewHabitDialogState extends State<_NewHabitDialog> {
  final _title = TextEditingController();
  final _steps = <({TextEditingController name, TimeOfDay? time})>[];

  @override
  void dispose() {
    _title.dispose();
    for (final s in _steps) {
      s.name.dispose();
    }
    super.dispose();
  }

  void _submit() {
    final title = _title.text.trim();
    if (title.isEmpty) return;
    Navigator.pop<_NewHabit>(context, (
      title: title,
      steps: [
        for (final s in _steps)
          if (s.name.text.trim().isNotEmpty)
            (name: s.name.text.trim(), time: s.time == null ? null : _hm(s.time!)),
      ],
    ));
  }

  Future<void> _pickTime(int i) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _steps[i].time ?? const TimeOfDay(hour: 9, minute: 0),
    );
    if (picked != null) setState(() => _steps[i] = (name: _steps[i].name, time: picked));
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return AlertDialog(
      title: const Text('New daily habit'),
      content: SizedBox(
        width: 360,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: 8,
            children: [
              TextField(
                key: const ValueKey('habit-title'),
                controller: _title,
                autofocus: true,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(hintText: 'Read 20 min, 5 meals, Water 4 L'),
                onSubmitted: (_) => _submit(),
              ),
              if (_steps.isNotEmpty)
                Text(
                  'Done for the day once every step is ticked. Each step reminds at its time.',
                  style: text.bodySmall?.copyWith(color: AppColors.muted),
                ),
              for (final (i, s) in _steps.indexed)
                Row(
                  spacing: 4,
                  children: [
                    Expanded(
                      child: TextField(
                        key: ValueKey('step-$i'),
                        controller: s.name,
                        textCapitalization: TextCapitalization.sentences,
                        decoration: InputDecoration(hintText: 'Step ${i + 1}', isDense: true),
                      ),
                    ),
                    TextButton(
                      onPressed: () => _pickTime(i),
                      child: Text(s.time == null ? 'Time' : _hm(s.time!)),
                    ),
                    IconButton(
                      tooltip: 'Remove step',
                      icon: const Icon(Icons.close, size: 18),
                      onPressed: () => setState(() => _steps.removeAt(i).name.dispose()),
                    ),
                  ],
                ),
              TextButton.icon(
                key: const ValueKey('add-step'),
                icon: const Icon(Icons.add, size: 18),
                label: Text(_steps.isEmpty ? 'Split into steps through the day' : 'Add another step'),
                onPressed: () => setState(() => _steps.add((name: TextEditingController(), time: null))),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(onPressed: _submit, child: const Text('Add')),
      ],
    );
  }
}

/// Habits only: a streak summary, then one tile per habit to tap done.
class HabitsPage extends StatelessWidget {
  const HabitsPage({super.key});

  Future<void> _add(BuildContext context) async {
    final made = await showDialog<_NewHabit>(context: context, builder: (context) => const _NewHabitDialog());
    if (made == null || !context.mounted) return;
    AppScope.of(context).change((s) {
      if (made.steps.isEmpty) {
        s.addHabit(title: made.title, startDate: today());
      }
      for (final step in made.steps) {
        s.addHabit(
          title: '${made.title}${Habit.groupSeparator}${step.name}',
          time: step.time,
          startDate: today(),
        );
      }
    });
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
    // Steps of one group ("5 meals / Lunch") share a tile, placed where the
    // group's first step falls in time order.
    final entries = <List<Habit>>[];
    final groups = <String, List<Habit>>{};
    for (final h in active) {
      final g = h.group;
      if (g == null) {
        entries.add([h]);
      } else if (groups.containsKey(g)) {
        groups[g]!.add(h);
      } else {
        entries.add(groups[g] = [h]);
      }
    }
    final doneToday = entries.where((e) => e.every((h) => checked.contains(h.id))).length;
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
                    Expanded(child: StatTile('$doneToday of ${entries.length}', 'Done today')),
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
        for (final e in entries) ...[
          const SizedBox(height: 10),
          if (e.first.group == null)
            _HabitTile(habit: e.first, done: checked.contains(e.first.id))
          else
            _GroupTile(title: e.first.group!, steps: e, checked: checked),
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

/// One habit made of several timed steps: each step is ticked on its own and
/// the habit is done for the day once all of them are.
class _GroupTile extends StatelessWidget {
  const _GroupTile({required this.title, required this.steps, required this.checked});

  final String title;
  final List<Habit> steps;
  final Set<String> checked;

  Future<void> _addStep(BuildContext context, AppState app) async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('New step in "$title"'),
        content: TextField(
          controller: controller,
          autofocus: true,
          textCapitalization: TextCapitalization.sentences,
          onSubmitted: (v) => Navigator.pop(context, v),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, controller.text), child: const Text('Next: time')),
        ],
      ),
    );
    if (name == null || name.trim().isEmpty || !context.mounted) return;
    final time = await showTimePicker(context: context, initialTime: const TimeOfDay(hour: 9, minute: 0));
    app.change((s) => s.addHabit(
          title: '$title${Habit.groupSeparator}${name.trim()}',
          time: time == null ? null : _hm(time),
          startDate: steps.first.startDate,
        ));
  }

  Future<void> _delete(BuildContext context, AppState app) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Delete "$title"?'),
        content: Text('All ${steps.length} steps and their history go with it.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Delete')),
        ],
      ),
    );
    if (ok == true) {
      app.change((s) {
        for (final h in steps) {
          s.deleteHabit(h.id);
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final text = Theme.of(context).textTheme;
    final now = today();
    final ids = [for (final h in steps) h.id];
    final doneCount = steps.where((h) => checked.contains(h.id)).length;
    final done = doneCount == steps.length;
    final streak = app.store.habitGroupStreak(ids, now);

    return Card(
      color: done ? AppColors.green.withValues(alpha: 0.16) : null,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 4, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              spacing: 14,
              children: [
                Container(
                  width: 34,
                  height: 34,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: done ? AppColors.green : Colors.transparent,
                    border: done ? null : Border.all(color: AppColors.muted, width: 2),
                  ),
                  child: done
                      ? const Icon(Icons.check_rounded, size: 22, color: AppColors.onLight)
                      : Text('$doneCount/${steps.length}', style: text.labelSmall?.copyWith(color: AppColors.muted)),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: text.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
                      Text(
                        '$doneCount of ${steps.length} today · ${streak.current}-day streak',
                        style: text.bodySmall?.copyWith(color: AppColors.muted),
                      ),
                    ],
                  ),
                ),
                PopupMenuButton<String>(
                  tooltip: 'More',
                  icon: const Icon(Icons.more_vert, color: AppColors.muted),
                  onSelected: (v) => v == 'step' ? _addStep(context, app) : _delete(context, app),
                  itemBuilder: (context) => const [
                    PopupMenuItem(value: 'step', child: Text('Add a step')),
                    PopupMenuItem(value: 'delete', child: Text('Delete')),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 4),
            for (final h in steps)
              InkWell(
                key: ValueKey('habit-${h.id}'),
                borderRadius: BorderRadius.circular(10),
                onTap: () => app.change((s) => s.setHabitCheck(h.id, now, !checked.contains(h.id))),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(6, 7, 8, 7),
                  child: Row(
                    spacing: 12,
                    children: [
                      Icon(
                        checked.contains(h.id) ? Icons.check_circle_rounded : Icons.circle_outlined,
                        size: 22,
                        color: checked.contains(h.id) ? AppColors.green : AppColors.muted,
                      ),
                      if (h.time != null)
                        Text(h.time!, style: text.bodyMedium?.copyWith(color: AppColors.muted)),
                      Expanded(child: Text(h.step, style: text.bodyMedium)),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
