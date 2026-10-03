import 'package:flutter/material.dart';
import 'package:todo_core/todo_core.dart';

import 'state.dart';
import 'task_widgets.dart';

/// Everything from today onward, grouped by day, then undated tasks.
class PlanPage extends StatefulWidget {
  const PlanPage({super.key});

  @override
  State<PlanPage> createState() => _PlanPageState();
}

class _PlanPageState extends State<PlanPage> {
  String? _listId;
  bool _showDone = false;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final theme = Theme.of(context);
    final lists = app.store.lists();
    if (!lists.any((l) => l.id == _listId)) _listId = null;
    final tasks = app.store.tasks(from: today(), undated: true, listId: _listId, includeDone: _showDone);

    final children = <Widget>[];
    String? heading;
    for (final t in tasks) {
      final h = t.date == null ? 'No date' : prettyDate(t.date!);
      if (h != heading) {
        heading = h;
        children.add(Padding(
          padding: const EdgeInsets.only(top: 16, bottom: 8),
          child: Text(h, style: theme.textTheme.titleSmall),
        ));
      }
      children
        ..add(TaskTile(t))
        ..add(const SizedBox(height: 8));
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
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              ChoiceChip(
                label: const Text('All lists'),
                selected: _listId == null,
                onSelected: (_) => setState(() => _listId = null),
              ),
              for (final l in lists)
                ChoiceChip(
                  label: Text(l.title),
                  selected: _listId == l.id,
                  onSelected: (_) => setState(() => _listId = l.id),
                ),
              FilterChip(
                label: const Text('Show done'),
                selected: _showDone,
                onSelected: (v) => setState(() => _showDone = v),
              ),
            ],
          ),
          if (tasks.isEmpty)
            const Padding(padding: EdgeInsets.only(top: 32), child: Center(child: Text('Nothing ahead.'))),
          ...children,
        ],
      ),
    );
  }
}
