import 'package:flutter/material.dart';
import 'package:todo_core/todo_core.dart';

import 'state.dart';
import 'timeline.dart' as timeline;

String timeLabel(Task t) => t.startTime == null
    ? ''
    : t.endTime == null
        ? t.startTime!
        : '${t.startTime}–${t.endTime}';

class TaskTile extends StatelessWidget {
  const TaskTile(this.task, {super.key, this.showDate = false});

  final Task task;
  final bool showDate;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final scheme = Theme.of(context).colorScheme;
    final details = [
      if (showDate && task.date != null) prettyDate(task.date!),
      timeLabel(task),
      ?task.tag,
      ?task.list,
    ].where((s) => s.isNotEmpty).join(' · ');
    // The task whose slot covers the present moment stands out as a block.
    final isNow = task.date != null && timeline.isNow(task.date!, task.startTime, task.endTime, done: task.done);
    return Card(
      color: isNow ? scheme.primary : null,
      child: ListTile(
        textColor: isNow ? scheme.onPrimary : null,
        iconColor: isNow ? scheme.onPrimary : null,
        contentPadding: const EdgeInsets.only(left: 4, right: 8),
        leading: Checkbox(
          side: isNow ? BorderSide(color: scheme.onPrimary, width: 2) : null,
          value: task.done,
          onChanged: (v) => app.change((s) => s.setDone(task.id, v ?? false)),
        ),
        title: Text(
          task.title,
          style: task.done
              ? TextStyle(decoration: TextDecoration.lineThrough, color: scheme.onSurfaceVariant)
              : null,
        ),
        subtitle: details.isEmpty && !isNow ? null : Text(isNow ? 'Now · $details' : details),
        trailing: task.done
            ? null
            : IconButton(
                tooltip: 'Start a 25 minute focus session on this',
                icon: const Icon(Icons.timer_outlined),
                onPressed: () {
                  app.change((s) => s.startFocus(taskId: task.id));
                  ScaffoldMessenger.of(context)
                      .showSnackBar(const SnackBar(content: Text('Focus started: 25 minutes')));
                },
              ),
        onTap: () => showTaskSheet(context, task: task),
      ),
    );
  }
}

Future<void> showTaskSheet(BuildContext context, {Task? task, String? date}) => showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => AppScope(state: AppScope.of(context), child: _TaskSheet(task: task, date: date)),
    );

class _TaskSheet extends StatefulWidget {
  const _TaskSheet({this.task, this.date});

  final Task? task;
  final String? date;

  @override
  State<_TaskSheet> createState() => _TaskSheetState();
}

class _TaskSheetState extends State<_TaskSheet> {
  late final _title = TextEditingController(text: widget.task?.title);
  late final _list = TextEditingController(text: widget.task?.list);
  late final _tag = TextEditingController(text: widget.task?.tag);
  late final _notes = TextEditingController(text: widget.task?.notes);
  late String? _date = widget.task?.date ?? widget.date;
  late String? _start = widget.task?.startTime;
  late String? _end = widget.task?.endTime;

  @override
  void dispose() {
    for (final c in [_title, _list, _tag, _notes]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _pickDate() async {
    final initial = _date == null ? DateTime.now() : parseYmd(_date!);
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (picked != null) setState(() => _date = ymd(picked));
  }

  Future<String?> _pickTime(String? current) async {
    final parts = (current ?? '09:00').split(':').map(int.parse).toList();
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: parts[0], minute: parts[1]),
    );
    if (picked == null) return current;
    return '${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}';
  }

  void _save() {
    final title = _title.text.trim();
    if (title.isEmpty) return;
    String? text(TextEditingController c) => c.text.trim().isEmpty ? null : c.text.trim();
    // A time needs a day to sit on.
    final date = _date ?? (_start == null ? null : today());
    AppScope.of(context).change((s) {
      final listId = text(_list) == null ? null : s.ensureList(text(_list)!).id;
      final task = widget.task;
      if (task == null) {
        s.addTask(
          title: title,
          date: date,
          startTime: _start,
          endTime: _start == null ? null : _end,
          listId: listId,
          tag: text(_tag),
          notes: text(_notes),
        );
      } else {
        s.updateTask(task.id, {
          'title': title,
          'date': date,
          'start_time': _start,
          'end_time': _start == null ? null : _end,
          'list_id': listId,
          'tag': text(_tag),
          'notes': text(_notes),
        });
      }
    });
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final task = widget.task;
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 0, 16, 16 + MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: 12,
          children: [
            TextField(
              controller: _title,
              autofocus: task == null,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(labelText: 'Task'),
              onSubmitted: (_) => _save(),
            ),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                InputChip(
                  avatar: const Icon(Icons.event, size: 18),
                  label: Text(_date == null ? 'No date' : prettyDate(_date!)),
                  onPressed: _pickDate,
                  onDeleted: _date == null ? null : () => setState(() => _date = null),
                ),
                InputChip(
                  avatar: const Icon(Icons.schedule, size: 18),
                  label: Text(_start ?? 'Start time'),
                  onPressed: () async {
                    final t = await _pickTime(_start);
                    setState(() => _start = t);
                  },
                  onDeleted: _start == null ? null : () => setState(() => _start = _end = null),
                ),
                if (_start != null)
                  InputChip(
                    label: Text(_end == null ? 'End time' : 'until $_end'),
                    onPressed: () async {
                      final t = await _pickTime(_end ?? _start);
                      setState(() => _end = t);
                    },
                    onDeleted: _end == null ? null : () => setState(() => _end = null),
                  ),
              ],
            ),
            Row(
              spacing: 12,
              children: [
                Expanded(
                  child: Autocomplete<String>(
                    initialValue: TextEditingValue(text: _list.text),
                    optionsBuilder: (v) => app.store
                        .lists()
                        .map((l) => l.title)
                        .where((t) => t.toLowerCase().contains(v.text.toLowerCase())),
                    onSelected: (v) => _list.text = v,
                    fieldViewBuilder: (context, controller, focus, _) => TextField(
                      controller: controller,
                      focusNode: focus,
                      decoration: const InputDecoration(labelText: 'List'),
                      onChanged: (v) => _list.text = v,
                    ),
                  ),
                ),
                Expanded(
                  child: TextField(controller: _tag, decoration: const InputDecoration(labelText: 'Tag')),
                ),
              ],
            ),
            TextField(
              controller: _notes,
              minLines: 1,
              maxLines: 4,
              decoration: const InputDecoration(labelText: 'Notes'),
            ),
            Row(
              children: [
                if (task != null)
                  TextButton.icon(
                    icon: const Icon(Icons.delete_outline),
                    label: const Text('Delete'),
                    style: TextButton.styleFrom(foregroundColor: Theme.of(context).colorScheme.error),
                    onPressed: () {
                      app.change((s) => s.deleteTask(task.id));
                      Navigator.pop(context);
                    },
                  ),
                const Spacer(),
                FilledButton(onPressed: _save, child: Text(task == null ? 'Add task' : 'Save')),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
