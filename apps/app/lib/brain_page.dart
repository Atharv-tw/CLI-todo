import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:vault_core/vault_core.dart';

import 'brain_icon.dart';
import 'markdown_view.dart';
import 'state.dart';
import 'theme.dart';

/// Your second brain, as far as the phone sees it: this morning's page, your
/// goals, this week and your projects. The notes themselves
/// live in the vault on the laptop; it publishes these on every sync.
class BrainPage extends StatelessWidget {
  const BrainPage({super.key});

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final store = app.store;
    final morning = store.page('morning');
    final weekly = store.page('weekly');
    final goals = store.page('goals')?.body.split('\n').where((g) => g.trim().isNotEmpty).toList() ?? const [];
    final projects = _projects(store.page('projects'));
    // Added here, not yet filed into the vault by the laptop.
    final waiting = store.requests();
    final newGoals = [for (final r in waiting) if (r.title == 'goal') r];
    final newProjects = [for (final r in waiting) if (r.title == 'project') r];
    final nothing = morning == null && weekly == null && goals.isEmpty && projects.isEmpty && waiting.isEmpty;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 96),
      children: [
        if (nothing) const _ConnectCard(),
        if (morning != null)
          _PageCard(
            key: const ValueKey('brain-morning'),
            label: morning.key == today() ? 'This morning' : 'Morning page, ${prettyDate(morning.key)}',
            page: morning,
            color: AppColors.cream,
          ),
        _Heading(
          'Goals',
          addKey: 'brain-add-goal',
          onAdd: () => _add(context, goal: true, taken: [for (final g in goals) _withoutDate(g)]),
        ),
        Card(
          key: const ValueKey('brain-goals'),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (goals.isEmpty && newGoals.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Text(
                      'No goals yet. Add what you are working towards; your agents plan around it.',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: AppColors.muted),
                    ),
                  ),
                for (final g in goals)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      spacing: 10,
                      children: [
                        const Padding(
                          padding: EdgeInsets.only(top: 2),
                          child: Icon(Icons.flag_rounded, size: 18, color: AppColors.orange),
                        ),
                        Expanded(child: Text(_withoutDate(g), style: Theme.of(context).textTheme.bodyLarge)),
                      ],
                    ),
                  ),
                for (final r in newGoals) _Waiting(r, title: _text(r)),
              ],
            ),
          ),
        ),
        if (weekly != null) ...[
          const _Heading('This week'),
          _PageCard(key: const ValueKey('brain-weekly'), label: weekly.title ?? weekly.key, page: weekly),
        ],
        _Heading(
          'Projects',
          trailing: projects.isEmpty ? null : '${projects.length}',
          addKey: 'brain-add-project',
          onAdd: () => _add(
            context,
            goal: false,
            taken: [for (final p in projects) p['name'] as String? ?? '', for (final r in newProjects) _text(r)],
          ),
        ),
        for (final r in newProjects) ...[
          Card(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 8, 4),
              child: _Waiting(r, title: _text(r), detail: _what(r)),
            ),
          ),
          const SizedBox(height: 8),
        ],
        if (projects.isEmpty && newProjects.isEmpty)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                'No projects yet. Start one; it gets its own notes and a work log your agents keep.',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: AppColors.muted),
              ),
            ),
          ),
        for (final p in projects) ...[_ProjectTile(p), const SizedBox(height: 8)],
        if (store.pages('morning').length > 1) ...[
          const _Heading('Earlier mornings'),
          for (final m in store.pages('morning').skip(1))
            ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 4),
              title: Text(prettyDate(m.key)),
              subtitle: Text(m.title ?? '', maxLines: 1, overflow: TextOverflow.ellipsis),
              trailing: const Icon(Icons.chevron_right_rounded, color: AppColors.muted),
              onTap: () => openPage(context, m),
            ),
        ],
      ],
    );
  }
}

String _text(VaultPage request) => _field(request, 'text') ?? '';
String? _what(VaultPage request) => _field(request, 'what');
String? _field(VaultPage request, String name) {
  try {
    return (jsonDecode(request.body) as Map)[name] as String?;
  } on FormatException {
    return null;
  }
}

/// Asks for a goal or a project, and leaves it for the laptop to file into
/// the vault, which the phone cannot write.
Future<void> _add(BuildContext context, {required bool goal, required List<String> taken}) async {
  final app = AppScope.of(context);
  final added = await showModalBottomSheet<(String, String)>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _AddSheet(goal: goal, taken: taken),
  );
  if (added == null) return;
  final (text, what) = added;
  app.change((s) => s.addRequest(goal ? 'goal' : 'project', {'text': text, if (what.isNotEmpty) 'what': what}));
}

String _withoutDate(String goal) => goal.replaceFirst(RegExp(r'\s*\(\d{4}-\d{2}-\d{2}\)\.?$'), '');

List<Map<String, Object?>> _projects(VaultPage? page) {
  if (page == null) return const [];
  try {
    return (jsonDecode(page.body) as List).cast<Map<String, Object?>>();
  } on FormatException {
    return const [];
  }
}

/// Opens a page from the vault full screen.
Future<void> openPage(BuildContext context, VaultPage page) => Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) => Scaffold(
          appBar: AppBar(title: Text(page.title ?? page.key)),
          body: SafeArea(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 760),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
                  child: MarkdownView(page.body),
                ),
              ),
            ),
          ),
        ),
      ),
    );

class _Heading extends StatelessWidget {
  const _Heading(this.text, {this.trailing, this.onAdd, this.addKey});

  final String text;
  final String? trailing;
  final VoidCallback? onAdd;
  final String? addKey;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 22, 4, 8),
      child: Row(
        children: [
          Expanded(child: Text(text, style: t.titleLarge?.copyWith(fontWeight: FontWeight.w700))),
          if (trailing != null) Text(trailing!, style: t.labelLarge?.copyWith(color: AppColors.muted)),
          if (onAdd != null) ...[
            const SizedBox(width: 8),
            IconButton.filledTonal(
              key: addKey == null ? null : ValueKey<String>(addKey!),
              tooltip: 'Add ${text.toLowerCase().replaceFirst(RegExp(r's$'), '')}',
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.add_rounded),
              onPressed: onAdd,
            ),
          ],
        ],
      ),
    );
  }
}

/// A morning or weekly page, shown in short; tap for all of it.
class _PageCard extends StatelessWidget {
  const _PageCard({super.key, required this.label, required this.page, this.color});

  final String label;
  final VaultPage page;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final light = color == AppColors.cream;
    final body = Theme(
      data: Theme.of(context).copyWith(
        textTheme: light ? t.apply(bodyColor: AppColors.onLight, displayColor: AppColors.onLight) : t,
      ),
      child: MarkdownView(firstSection(page.body), maxBlocks: 8),
    );
    return Material(
      color: color ?? AppColors.card,
      borderRadius: BorderRadius.circular(cardRadius),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => openPage(context, page),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: 6,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      label,
                      style: t.labelLarge?.copyWith(
                        color: light ? AppColors.onLight.withValues(alpha: 0.65) : AppColors.muted,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  Text(
                    'Read all',
                    style: t.labelLarge?.copyWith(color: light ? AppColors.onLight : AppColors.orange),
                  ),
                ],
              ),
              body,
            ],
          ),
        ),
      ),
    );
  }
}

/// The page's first section after its title: for a morning page, the day.
String firstSection(String body) {
  final lines = body.split('\n');
  final start = lines.indexWhere((l) => l.startsWith('## '));
  if (start < 0) return lines.where((l) => !l.startsWith('# ')).join('\n');
  final end = lines.indexWhere((l) => l.startsWith('## '), start + 1);
  return lines.sublist(start, end < 0 ? lines.length : end).join('\n');
}

class _ProjectTile extends StatelessWidget {
  const _ProjectTile(this.project);

  final Map<String, Object?> project;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final name = project['name'] as String? ?? '';
    final status = project['status'] as String?;
    final what = project['what'] as String?;
    final color = switch (status) {
      'building' => AppColors.orange,
      'role' => AppColors.lavender,
      'paused' => AppColors.muted,
      _ => AppColors.green,
    };
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => showModalBottomSheet<void>(
          context: context,
          isScrollControlled: true,
          showDragHandle: true,
          builder: (sheet) => DraggableScrollableSheet(
            expand: false,
            initialChildSize: 0.7,
            maxChildSize: 0.95,
            builder: (_, scroll) => SingleChildScrollView(
              controller: scroll,
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
              child: MarkdownView(project['overview'] as String? ?? '# $name'),
            ),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
          child: Row(
            spacing: 12,
            children: [
              Container(width: 4, height: 40, decoration: ShapeDecoration(color: color, shape: const StadiumBorder())),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  spacing: 2,
                  children: [
                    Text(name, style: t.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                    if (what != null && what.isNotEmpty)
                      Text(
                        what,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: t.bodySmall?.copyWith(color: AppColors.muted),
                      ),
                  ],
                ),
              ),
              if (status != null)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                  decoration: ShapeDecoration(color: color.withValues(alpha: 0.18), shape: const StadiumBorder()),
                  child: Text(status, style: t.labelSmall?.copyWith(color: color, fontWeight: FontWeight.w700)),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Shown until the laptop has published anything: how to connect the notes.
class _ConnectCard extends StatelessWidget {
  const _ConnectCard();

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Card(
      key: const ValueKey('brain-connect'),
      color: AppColors.lavender.withValues(alpha: 0.14),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: 8,
          children: [
            const BrainIcon(color: AppColors.lavender, size: 34),
            Text('Your second brain shows up here', style: t.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
            Text(
              'Your notes live in a vault on your laptop: you, your goals, projects, people, what you learned. '
              'Every night your agent files your diary into it and writes a morning page with the day\'s plan. '
              'This phone shows those pages, your goals and your projects after each sync.',
              style: t.bodyMedium?.copyWith(height: 1.4),
            ),
            Text('On your laptop:', style: t.labelLarge?.copyWith(color: AppColors.muted)),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: AppColors.raised, borderRadius: BorderRadius.circular(12)),
              child: const Text('myvault init\nmyvault sync', style: TextStyle(fontFamily: 'monospace')),
            ),
          ],
        ),
      ),
    );
  }
}

/// A goal or project added here that the laptop has not filed yet. It can
/// still be taken back.
class _Waiting extends StatelessWidget {
  const _Waiting(this.request, {required this.title, this.detail});

  final VaultPage request;
  final String title;
  final String? detail;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Row(
      key: ValueKey('waiting-${request.id}'),
      spacing: 10,
      children: [
        const Icon(Icons.schedule_rounded, size: 18, color: AppColors.muted),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: 2,
            children: [
              Text(title, style: t.bodyLarge),
              if (detail != null && detail!.isNotEmpty)
                Text(detail!, maxLines: 2, overflow: TextOverflow.ellipsis, style: t.bodySmall?.copyWith(color: AppColors.muted)),
              Text(
                'Goes into your notes when your laptop syncs',
                style: t.labelSmall?.copyWith(color: AppColors.muted),
              ),
            ],
          ),
        ),
        IconButton(
          key: ValueKey('waiting-${request.id}-remove'),
          tooltip: 'Take back',
          icon: const Icon(Icons.close_rounded, size: 20, color: AppColors.muted),
          onPressed: () => AppScope.of(context).change((s) => s.deletePage(request.id)),
        ),
      ],
    );
  }
}

/// The sheet for a new goal (one line) or project (a name and what it is).
class _AddSheet extends StatefulWidget {
  const _AddSheet({required this.goal, required this.taken});

  final bool goal;
  final List<String> taken;

  @override
  State<_AddSheet> createState() => _AddSheetState();
}

class _AddSheetState extends State<_AddSheet> {
  final _text = TextEditingController();
  final _what = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _text.dispose();
    _what.dispose();
    super.dispose();
  }

  void _save() {
    final text = _text.text.trim();
    if (text.isEmpty) return setState(() => _error = widget.goal ? 'Write the goal.' : 'Give it a name.');
    if (widget.taken.any((x) => x.toLowerCase() == text.toLowerCase())) {
      return setState(() => _error = widget.goal ? 'That goal is already there.' : 'There is a project by that name.');
    }
    Navigator.pop(context, (text, _what.text.trim()));
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + MediaQuery.viewInsetsOf(context).bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 12,
        children: [
          Text(widget.goal ? 'A new goal' : 'A new project', style: t.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
          Text(
            widget.goal
                ? 'Something you are working towards. It goes into Me.md, and your agents plan around it.'
                : 'It gets its own folder in your notes, with an overview and a work log your agents keep.',
            style: t.bodyMedium?.copyWith(color: AppColors.muted),
          ),
          TextField(
            key: ValueKey(widget.goal ? 'goal-text' : 'project-name'),
            controller: _text,
            autofocus: true,
            textCapitalization: TextCapitalization.sentences,
            textInputAction: widget.goal ? TextInputAction.done : TextInputAction.next,
            onSubmitted: widget.goal ? (_) => _save() : null,
            decoration: InputDecoration(
              labelText: widget.goal ? 'Goal' : 'Name',
              hintText: widget.goal ? 'Land an ML internship by March' : 'Helios',
              errorText: _error,
            ),
          ),
          if (!widget.goal)
            TextField(
              key: const ValueKey('project-what'),
              controller: _what,
              textCapitalization: TextCapitalization.sentences,
              minLines: 1,
              maxLines: 3,
              onSubmitted: (_) => _save(),
              decoration: const InputDecoration(labelText: 'What it is (optional)', hintText: 'Security scanning that ships fixes'),
            ),
          FilledButton(
            key: ValueKey(widget.goal ? 'goal-save' : 'project-save'),
            onPressed: _save,
            child: Text(widget.goal ? 'Add goal' : 'Start project'),
          ),
        ],
      ),
    );
  }
}
