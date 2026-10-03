import 'dart:async';

import 'package:flutter/material.dart';
import 'package:todo_core/todo_core.dart';

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
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: 12,
              children: [
                Expanded(flex: 11, child: _UpNextCard(items: items, date: date)),
                const Expanded(flex: 10, child: _FocusCard()),
              ],
            ),
          ),
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

class _Hero extends StatelessWidget {
  const _Hero({required this.color, required this.child});

  final Color color;
  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
        constraints: const BoxConstraints(minHeight: 190),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(cardRadius)),
        child: child,
      );
}

/// Orange card: the current or next few unticked items, each tickable.
class _UpNextCard extends StatelessWidget {
  const _UpNextCard({required this.items, required this.date});

  final List<Map<String, Object?>> items;
  final String date;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final text = Theme.of(context).textTheme;
    final nowHm = hm(DateTime.now());
    final open = items.where((i) => i['done'] != true).toList();
    // Start from whatever is running or still ahead; fall back to what is left.
    final ahead = open.where((i) {
      final time = i['time'] as String?;
      if (time == null || date != today()) return true;
      return hm(slotEnd(date, time, i['end_time'] as String?)).compareTo(nowHm) > 0;
    }).toList();
    final shown = (ahead.isEmpty ? open : ahead).take(3).toList();
    final running = shown.isNotEmpty &&
        isNow(date, shown.first['time'] as String?, shown.first['end_time'] as String?, done: false);

    return _Hero(
      color: AppColors.orange,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            running ? 'Now' : 'Up next',
            style: text.titleMedium?.copyWith(color: Colors.white, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 10),
          if (shown.isEmpty)
            Expanded(
              child: Center(
                child: Text(
                  items.isEmpty ? 'Nothing planned' : 'All done',
                  style: text.titleMedium?.copyWith(color: Colors.white),
                ),
              ),
            ),
          for (final i in shown)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Material(
                color: Colors.white.withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(16),
                child: InkWell(
                  borderRadius: BorderRadius.circular(16),
                  onTap: () => app.change(
                    (s) => i['kind'] == 'habit'
                        ? s.setHabitCheck(i['id'] as String, date, true)
                        : s.setDone(i['id'] as String, true),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    child: Row(
                      spacing: 8,
                      children: [
                        const Icon(Icons.radio_button_unchecked, size: 18, color: Colors.white),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                i['title'] as String,
                                maxLines: i == shown.first ? 2 : 1,
                                overflow: TextOverflow.ellipsis,
                                style: text.bodyMedium?.copyWith(color: Colors.white, fontWeight: FontWeight.w600),
                              ),
                              if (i['time'] != null)
                                Text(
                                  i['time'] as String,
                                  style: text.labelSmall?.copyWith(color: Colors.white.withValues(alpha: 0.8)),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Lavender card: start a focus session, or watch the running one.
class _FocusCard extends StatefulWidget {
  const _FocusCard();

  @override
  State<_FocusCard> createState() => _FocusCardState();
}

class _FocusCardState extends State<_FocusCard> {
  late final Timer _tick = Timer.periodic(const Duration(seconds: 1), (_) => setState(() {}));

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
    final session = app.store.currentFocus();
    final minutes = app.store.focusedMinutes(today());
    final left = session?.plannedEnd.difference(DateTime.now());
    const dark = AppColors.onLight;

    return _Hero(
      color: AppColors.lavender,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            session == null ? 'Focus' : (session.kind == 'break' ? 'Break' : 'Focusing'),
            style: text.labelLarge?.copyWith(color: dark.withValues(alpha: 0.7)),
          ),
          const SizedBox(height: 4),
          Expanded(
            child: session == null
                ? Text(
                    minutes == 0 ? 'Start a 25 minute session' : '$minutes min focused today',
                    style: text.titleLarge?.copyWith(color: dark, fontWeight: FontWeight.w700, height: 1.15),
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${left!.inMinutes}:${(left.inSeconds % 60).toString().padLeft(2, '0')}',
                        style: text.displaySmall?.copyWith(
                          color: dark,
                          fontWeight: FontWeight.w800,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                      if (session.taskTitle != null)
                        Text(
                          session.taskTitle!,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: text.bodySmall?.copyWith(color: dark),
                        ),
                    ],
                  ),
          ),
          Material(
            color: AppColors.cream,
            shape: const StadiumBorder(),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: () => app.change((s) => session == null ? s.startFocus() : s.stopFocus()),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 4, 4),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        session == null ? 'Start' : 'Stop',
                        style: text.labelLarge?.copyWith(color: dark, fontWeight: FontWeight.w600),
                      ),
                    ),
                    CircleAvatar(
                      radius: 16,
                      backgroundColor: dark,
                      child: Icon(
                        session == null ? Icons.play_arrow : Icons.stop,
                        size: 18,
                        color: AppColors.cream,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
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
