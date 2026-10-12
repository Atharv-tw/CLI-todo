import 'package:flutter/material.dart';
import 'package:todo_core/todo_core.dart';

import 'state.dart';
import 'task_widgets.dart';
import 'theme.dart';

/// The next seven days, grouped by day. Anything further out (and undated
/// tasks) sits folded under "Later", so the page answers "what is coming up"
/// without listing months of deadlines.
class PlanPage extends StatefulWidget {
  const PlanPage({super.key});

  @override
  State<PlanPage> createState() => _PlanPageState();
}

class _PlanPageState extends State<PlanPage> {
  bool _showDone = false;

  static const _days = 7;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final text = Theme.of(context).textTheme;
    final now = today();
    final last = addDays(now, _days - 1);
    final week = app.store.tasks(from: now, to: last, includeDone: _showDone);
    final later = app.store.tasks(from: addDays(last, 1), undated: true, includeDone: _showDone);

    List<Widget> grouped(List<Task> tasks) {
      final out = <Widget>[];
      String? heading;
      for (final t in tasks) {
        final h = t.date == null
            ? 'No date'
            : t.date == now
                ? 'Today'
                : t.date == addDays(now, 1)
                    ? 'Tomorrow'
                    : prettyDate(t.date!);
        if (h != heading) {
          heading = h;
          out.add(Padding(
            padding: const EdgeInsets.only(top: 16, bottom: 8),
            child: Text(h, style: text.titleSmall),
          ));
        }
        out
          ..add(TaskTile(t))
          ..add(const SizedBox(height: 8));
      }
      return out;
    }

    return Scaffold(
      floatingActionButton: FloatingActionButton(
        tooltip: 'Add task',
        shape: const CircleBorder(),
        onPressed: () => showTaskSheet(context),
        child: const Icon(Icons.add),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
        children: [
          Row(
            children: [
              Expanded(
                child: Text('Next $_days days', style: text.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
              ),
              FilterChip(
                label: const Text('Show done'),
                selected: _showDone,
                onSelected: (v) => setState(() => _showDone = v),
              ),
            ],
          ),
          if (week.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 32),
              child: Center(child: Text('Nothing this week.', style: TextStyle(color: AppColors.muted))),
            ),
          ...grouped(week),
          if (later.isNotEmpty)
            ExpansionTile(
              key: const ValueKey('later'),
              tilePadding: const EdgeInsets.symmetric(horizontal: 4),
              shape: const Border(),
              title: Text(
                'Later  ·  ${later.length}',
                style: text.titleSmall?.copyWith(color: AppColors.muted),
              ),
              children: grouped(later),
            ),
        ],
      ),
    );
  }
}
