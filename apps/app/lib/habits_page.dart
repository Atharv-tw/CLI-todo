import 'package:flutter/material.dart';
import 'package:todo_core/todo_core.dart';

import 'state.dart';

/// Habits against the last few days, like the grid on the 90-day page.
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
    final theme = Theme.of(context);
    final now = today();
    final habits = app.store.habits(activeOn: now);

    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        icon: const Icon(Icons.add),
        label: const Text('Habit'),
        onPressed: () => _add(context),
      ),
      body: LayoutBuilder(builder: (context, box) {
        final dayCount = box.maxWidth >= 600 ? 7 : 4;
        final days = [for (var i = dayCount - 1; i >= 0; i--) addDays(now, -i)];
        final checked = {for (final d in days) d: app.store.checkedHabitIds(d)};
        final active = {for (final d in days) d: app.store.habits(activeOn: d).map((h) => h.id).toSet()};
        const cell = 44.0;

        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
          children: [
            Row(
              children: [
                const Spacer(),
                for (final d in days)
                  SizedBox(
                    width: cell,
                    child: Text(
                      d == now ? 'Today' : prettyDate(d).split(' ').take(2).join(' '),
                      textAlign: TextAlign.center,
                      style: theme.textTheme.labelSmall?.copyWith(
                        fontWeight: d == now ? FontWeight.w700 : null,
                        color: d == now ? theme.colorScheme.primary : theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            if (habits.isEmpty)
              const Padding(padding: EdgeInsets.only(top: 32), child: Center(child: Text('No habits yet.'))),
            for (final h in habits) ...[
              Card(
                child: Padding(
                  padding: const EdgeInsets.only(left: 12),
                  child: Row(
                    children: [
                      Expanded(
                        child: GestureDetector(
                          onLongPress: () async {
                            final ok = await showDialog<bool>(
                              context: context,
                              builder: (context) => AlertDialog(
                                title: Text('Delete "${h.title}"?'),
                                actions: [
                                  TextButton(
                                      onPressed: () => Navigator.pop(context, false),
                                      child: const Text('Cancel')),
                                  FilledButton(
                                      onPressed: () => Navigator.pop(context, true),
                                      child: const Text('Delete')),
                                ],
                              ),
                            );
                            if (ok == true) app.change((s) => s.deleteHabit(h.id));
                          },
                          child: Text(h.title, style: theme.textTheme.bodyLarge),
                        ),
                      ),
                      for (final d in days)
                        SizedBox(
                          width: cell,
                          height: 48,
                          child: active[d]!.contains(h.id)
                              ? Checkbox(
                                  value: checked[d]!.contains(h.id),
                                  onChanged: (v) => app.change((s) => s.setHabitCheck(h.id, d, v ?? false)),
                                )
                              : Center(
                                  child: Text('–', style: TextStyle(color: theme.colorScheme.onSurfaceVariant)),
                                ),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 8),
            ],
          ],
        );
      }),
    );
  }
}
