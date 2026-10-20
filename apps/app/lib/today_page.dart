import 'dart:async';

import 'package:flutter/material.dart';
import 'package:vault_core/vault_core.dart';

import 'brain_page.dart';
import 'diary_page.dart';
import 'heatmap.dart';
import 'markdown_view.dart';
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

  /// The + button has been opened into the diary box.
  bool _logging = false;

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

    return Scaffold(
      floatingActionButton: _logging
          ? null
          : FloatingActionButton(
              key: const ValueKey('quick-log'),
              tooltip: 'Log an entry',
              shape: const CircleBorder(),
              onPressed: () => setState(() => _logging = true),
              child: const Icon(Icons.add),
            ),
      body: Stack(
        children: [
          ListView(
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
              if (app.store.page('morning', date) case final morning?) ...[
                _MorningCard(morning),
                const SizedBox(height: 12),
              ],
              _ActivityCard(selected: date, onPick: (d) => setState(() => _picked = d == now ? null : d)),
              const SizedBox(height: 12),
              _NowCard(date: date, items: items, tasks: tasks, overdue: overdue.length),
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
                  child: Center(
                    child: Text('Nothing scheduled', style: TextStyle(color: AppColors.muted)),
                  ),
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
          if (_logging)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: _QuickLog(
                onClose: () => setState(() => _logging = false),
                onSaved: () {
                  setState(() => _logging = false);
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Saved to the diary')));
                },
                onAddTask: () {
                  setState(() => _logging = false);
                  showTaskSheet(context, date: date);
                },
              ),
            ),
        ],
      ),
    );
  }
}

/// The + button opened up: a diary box right on the page, to log whatever
/// is on your mind without leaving it. A task can still be added from here.
class _QuickLog extends StatelessWidget {
  const _QuickLog({required this.onClose, required this.onSaved, required this.onAddTask});

  final VoidCallback onClose;
  final VoidCallback onSaved;
  final VoidCallback onAddTask;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Material(
      key: const ValueKey('quick-log-bar'),
      elevation: 6,
      color: AppColors.raised,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(cardRadius)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(child: Text('Log an entry', style: text.titleSmall)),
                TextButton(
                  key: const ValueKey('quick-log-task'),
                  onPressed: onAddTask,
                  child: const Text('Add a task instead'),
                ),
                IconButton(tooltip: 'Close', icon: const Icon(Icons.close_rounded), onPressed: onClose),
              ],
            ),
            DiaryComposer(autofocus: true, onSaved: onSaved),
          ],
        ),
      ),
    );
  }
}

/// The day's morning page from the vault: its plan, in short. Tap for all
/// of it: facts, guesses, what waits for your yes, open questions.
class _MorningCard extends StatelessWidget {
  const _MorningCard(this.page);

  final VaultPage page;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Material(
      key: const ValueKey('morning-card'),
      color: AppColors.lavender.withValues(alpha: 0.14),
      borderRadius: BorderRadius.circular(cardRadius),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => openPage(context, page),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: 4,
            children: [
              Row(
                spacing: 8,
                children: [
                  const Icon(Icons.wb_sunny_rounded, size: 18, color: AppColors.lavender),
                  Expanded(
                    child: Text(
                      'Your morning page',
                      style: t.labelLarge?.copyWith(color: AppColors.lavender, fontWeight: FontWeight.w800),
                    ),
                  ),
                  Text('Read all', style: t.labelLarge?.copyWith(color: AppColors.muted)),
                ],
              ),
              MarkdownView(firstSection(page.body), maxBlocks: 6),
            ],
          ),
        ),
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

/// Cream card: a ring with how much of the day is done and, beside it, the
/// task to be on right now (or the next one, when nothing is on).
class _NowCard extends StatelessWidget {
  const _NowCard({required this.date, required this.items, required this.tasks, required this.overdue});

  final String date;

  /// The day's timeline, in time order (`Store.snapshot()['items']`).
  final List<Map<String, Object?>> items;
  final Map<String, Task> tasks;
  final int overdue;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final text = Theme.of(context).textTheme;
    const dark = AppColors.onLight;
    final done = items.where((i) => i['done'] == true).length;
    final total = items.length;
    final onToday = date == today();

    // The unticked task whose slot covers this moment (the latest-starting
    // one if they overlap), else the next one still to come today.
    Map<String, Object?>? current, next;
    if (onToday) {
      final now = DateTime.now();
      for (final i in items) {
        final time = i['time'] as String?;
        if (i['kind'] != 'task' || i['done'] == true || time == null) continue;
        if (isNow(date, time, i['end_time'] as String?, done: false)) {
          current = i;
        } else if (atTime(date, time).isAfter(now)) {
          next ??= i;
        }
      }
    }
    final shown = current ?? next;
    final task = shown == null ? null : tasks[shown['id']];

    final String? pill;
    final String label;
    final String title;
    if (current != null) {
      pill = 'NOW';
      label = 'until ${hm(slotEnd(date, current['time'] as String, current['end_time'] as String?))}';
      title = current['title'] as String;
    } else if (next != null) {
      pill = 'NEXT';
      label = 'at ${next['time']}';
      title = next['title'] as String;
    } else {
      pill = null;
      label = onToday ? 'Today' : prettyDate(date);
      title = total == 0
          ? 'Nothing scheduled'
          : done == total
          ? 'All done'
          : onToday
          ? 'Nothing on right now'
          : '${total - done} left undone';
    }
    final details = [?task?.tag, ?task?.list].join(' · ');

    return Material(
      key: const ValueKey('now-card'),
      color: AppColors.cream,
      borderRadius: BorderRadius.circular(cardRadius),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: task == null ? null : () => showTaskSheet(context, task: task),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 14, 10, 14),
          child: Row(
            spacing: 14,
            children: [
              SizedBox.square(
                dimension: 66,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    CircularProgressIndicator(
                      value: total == 0 ? 0 : done / total,
                      strokeWidth: 6,
                      strokeCap: StrokeCap.round,
                      color: AppColors.orange,
                      backgroundColor: dark.withValues(alpha: 0.12),
                    ),
                    Center(
                      child: Text(
                        '$done/$total',
                        semanticsLabel: '$done of $total done',
                        style: text.titleSmall?.copyWith(
                          color: dark,
                          fontWeight: FontWeight.w800,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      spacing: 8,
                      children: [
                        if (pill != null)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: ShapeDecoration(
                              color: current != null ? AppColors.orange : dark,
                              shape: const StadiumBorder(),
                            ),
                            child: Text(
                              pill,
                              style: text.labelSmall?.copyWith(
                                color: Colors.white,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 0.6,
                              ),
                            ),
                          ),
                        Flexible(
                          child: Text(
                            label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: text.labelLarge?.copyWith(color: dark.withValues(alpha: 0.65)),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: text.titleMedium?.copyWith(color: dark, fontWeight: FontWeight.w700, height: 1.2),
                    ),
                    if (details.isNotEmpty || overdue > 0)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text.rich(
                          TextSpan(
                            children: [
                              if (details.isNotEmpty) TextSpan(text: details),
                              if (details.isNotEmpty && overdue > 0) const TextSpan(text: '  ·  '),
                              if (overdue > 0)
                                TextSpan(
                                  text: '$overdue overdue',
                                  style: const TextStyle(color: Color(0xFFB3261E), fontWeight: FontWeight.w600),
                                ),
                            ],
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: text.bodySmall?.copyWith(color: dark.withValues(alpha: 0.6)),
                        ),
                      ),
                  ],
                ),
              ),
              if (current != null)
                IconButton.filled(
                  key: const ValueKey('now-done'),
                  tooltip: 'Mark done',
                  style: IconButton.styleFrom(backgroundColor: dark, foregroundColor: AppColors.cream),
                  icon: const Icon(Icons.check_rounded),
                  onPressed: () => app.change((s) => s.setDone(current!['id'] as String, true)),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
