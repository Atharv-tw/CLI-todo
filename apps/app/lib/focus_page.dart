import 'dart:async';

import 'package:flutter/material.dart';
import 'package:todo_core/todo_core.dart';

import 'state.dart';

class FocusPage extends StatefulWidget {
  const FocusPage({super.key});

  @override
  State<FocusPage> createState() => _FocusPageState();
}

class _FocusPageState extends State<FocusPage> {
  late final Timer _tick = Timer.periodic(const Duration(seconds: 1), (_) => setState(() {}));
  int _minutes = 25;
  String? _taskId;

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
    final theme = Theme.of(context);
    final session = app.store.currentFocus();
    final focused = app.store.focusedMinutes(today());

    final Widget body;
    if (session != null) {
      final left = session.plannedEnd.difference(DateTime.now());
      final total = session.plannedMin * 60;
      final isBreak = session.kind == 'break';
      body = Column(
        mainAxisSize: MainAxisSize.min,
        spacing: 24,
        children: [
          SizedBox.square(
            dimension: 240,
            child: Stack(
              fit: StackFit.expand,
              children: [
                CircularProgressIndicator(
                  value: 1 - left.inSeconds / total,
                  strokeWidth: 10,
                  strokeCap: StrokeCap.round,
                  color: isBreak ? theme.colorScheme.secondary : null,
                  backgroundColor: theme.colorScheme.surfaceContainerHighest,
                ),
                Center(
                  child: Text(
                    '${left.inMinutes}:${(left.inSeconds % 60).toString().padLeft(2, '0')}',
                    style: theme.textTheme.displayLarge?.copyWith(
                      fontFeatures: const [FontFeature.tabularFigures()],
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Text(
            isBreak ? 'Break' : session.taskTitle ?? 'Focus',
            textAlign: TextAlign.center,
            style: theme.textTheme.titleMedium,
          ),
          FilledButton.tonalIcon(
            icon: const Icon(Icons.stop),
            label: const Text('Stop'),
            onPressed: () => app.change((s) => s.stopFocus()),
          ),
        ],
      );
    } else {
      final open = app.store.tasks(from: today(), to: today(), includeDone: false);
      if (!open.any((t) => t.id == _taskId)) _taskId = null;
      body = Column(
        mainAxisSize: MainAxisSize.min,
        spacing: 20,
        children: [
          SegmentedButton<int>(
            segments: const [
              ButtonSegment(value: 15, label: Text('15 min')),
              ButtonSegment(value: 25, label: Text('25 min')),
              ButtonSegment(value: 50, label: Text('50 min')),
            ],
            selected: {_minutes},
            onSelectionChanged: (v) => setState(() => _minutes = v.first),
          ),
          if (open.isNotEmpty)
            DropdownMenu<String?>(
              width: 320,
              label: const Text('Working on'),
              initialSelection: _taskId,
              onSelected: (v) => setState(() => _taskId = v),
              dropdownMenuEntries: [
                const DropdownMenuEntry(value: null, label: 'No particular task'),
                for (final t in open) DropdownMenuEntry(value: t.id, label: t.title),
              ],
            ),
          FilledButton.icon(
            icon: const Icon(Icons.play_arrow),
            label: const Text('Start focus'),
            onPressed: () => app.change((s) => s.startFocus(taskId: _taskId, minutes: _minutes)),
          ),
          TextButton(
            onPressed: () => app.change((s) => s.startFocus(minutes: 5, kind: 'break')),
            child: const Text('Take a 5 minute break'),
          ),
        ],
      );
    }

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          spacing: 24,
          children: [
            body,
            Text(
              '$focused min focused today',
              style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}
