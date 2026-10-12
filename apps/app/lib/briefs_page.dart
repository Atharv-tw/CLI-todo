import 'package:flutter/material.dart';
import 'package:todo_core/todo_core.dart';

import 'state.dart';
import 'theme.dart';

/// The daily brief: write how the day went and what should change, and read
/// back what the assistant did about it. Older days stay below for review.
class BriefsPage extends StatefulWidget {
  const BriefsPage({super.key});

  @override
  State<BriefsPage> createState() => _BriefsPageState();
}

class _BriefsPageState extends State<BriefsPage> {
  final _draft = TextEditingController();

  @override
  void dispose() {
    _draft.dispose();
    super.dispose();
  }

  void _save(AppState app) {
    final body = _draft.text.trim();
    if (body.isEmpty) return;
    app.change((s) => s.addBrief(body));
    _draft.clear();
    FocusScope.of(context).unfocus();
  }

  Future<void> _edit(AppState app, Brief b) async {
    final controller = TextEditingController(text: b.body);
    final body = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Brief for ${prettyDate(b.date)}'),
        content: SizedBox(
          width: 420,
          child: TextField(controller: controller, autofocus: true, minLines: 3, maxLines: 10),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, controller.text), child: const Text('Save')),
        ],
      ),
    );
    if (body != null && body.trim().isNotEmpty) app.change((s) => s.updateBrief(b.id, body));
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final text = Theme.of(context).textTheme;
    final now = today();
    final briefs = app.store.briefs(from: addDays(now, -90));

    final children = <Widget>[
      Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: 12,
            children: [
              Text('Today, ${prettyDate(now)}', style: text.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
              TextField(
                key: const ValueKey('brief-draft'),
                controller: _draft,
                minLines: 3,
                maxLines: 8,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  hintText: 'When did you wake up? What got done, what did not, what should change?',
                ),
              ),
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton(onPressed: () => _save(app), child: const Text('Save brief')),
              ),
            ],
          ),
        ),
      ),
      if (briefs.isEmpty)
        Padding(
          padding: const EdgeInsets.only(top: 32),
          child: Text(
            'Nothing written yet. Your briefs and the changes made from them will collect here.',
            textAlign: TextAlign.center,
            style: text.bodyMedium?.copyWith(color: AppColors.muted),
          ),
        ),
    ];

    String? day;
    for (final b in briefs) {
      if (b.date != day) {
        day = b.date;
        children.add(Padding(
          padding: const EdgeInsets.fromLTRB(4, 20, 4, 8),
          child: Text(b.date == now ? 'Today' : prettyDate(b.date), style: text.titleSmall),
        ));
      }
      final mine = b.author == Brief.me;
      children
        ..add(Card(
          color: mine ? null : AppColors.lavender.withValues(alpha: 0.14),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 4, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        mine ? 'You' : 'Claude',
                        style: text.labelLarge?.copyWith(
                          color: mine ? AppColors.muted : AppColors.lavender,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    PopupMenuButton<String>(
                      tooltip: 'More',
                      icon: const Icon(Icons.more_vert, size: 20, color: AppColors.muted),
                      onSelected: (v) =>
                          v == 'edit' ? _edit(app, b) : app.change((s) => s.deleteBrief(b.id)),
                      itemBuilder: (context) => [
                        if (mine) const PopupMenuItem(value: 'edit', child: Text('Edit')),
                        const PopupMenuItem(value: 'delete', child: Text('Delete')),
                      ],
                    ),
                  ],
                ),
                Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: SelectableText(b.body, style: text.bodyMedium),
                ),
              ],
            ),
          ),
        ))
        ..add(const SizedBox(height: 8));
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Daily brief')),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 24), children: children),
          ),
        ),
      ),
    );
  }
}
