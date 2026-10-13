import 'package:flutter/material.dart';
import 'package:todo_core/todo_core.dart';

import 'state.dart';
import 'theme.dart';
import 'voice.dart';
import 'voice_sheet.dart';

/// Opens the composer as a sheet, for an entry about [task] or [habit], or
/// about nothing in particular. With [listen] it starts hearing at once.
Future<void> showDiaryComposer(BuildContext context, {Task? task, Habit? habit, bool listen = false}) =>
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheet) => AppScope(
        state: AppScope.of(context),
        child: Padding(
          padding: EdgeInsets.fromLTRB(16, 0, 16, 16 + MediaQuery.viewInsetsOf(sheet).bottom),
          child: DiaryComposer(
            taskId: task?.id,
            habitId: habit?.id,
            about: task?.title ?? habit?.title,
            listen: listen,
            autofocus: !listen,
            onSaved: () => Navigator.pop(sheet),
          ),
        ),
      ),
    );

/// Where a diary entry is written or spoken. The mic turns speech into text
/// in the same box, so it can be corrected before saving.
class DiaryComposer extends StatefulWidget {
  const DiaryComposer({
    super.key,
    this.taskId,
    this.habitId,
    this.about,
    this.listen = false,
    this.autofocus = false,
    this.onSaved,
  });

  final String? taskId;
  final String? habitId;

  /// Title of the task or habit the entry is about, shown above the box.
  final String? about;
  final bool listen;
  final bool autofocus;
  final VoidCallback? onSaved;

  @override
  State<DiaryComposer> createState() => _DiaryComposerState();
}

class _DiaryComposerState extends State<DiaryComposer> {
  final _text = TextEditingController();

  /// The speech engine last used here; made when the mic is first pressed.
  Dictation? _dictation;

  /// What was in the box when the mic was pressed; speech is added after it.
  String _before = '';

  @override
  void initState() {
    super.initState();
    if (widget.listen && voiceSupported) WidgetsBinding.instance.addPostFrameCallback((_) => _toggleMic());
  }

  @override
  void dispose() {
    _dictation
      ?..removeListener(_heard)
      ..dispose();
    _text.dispose();
    super.dispose();
  }

  void _heard() {
    final dictation = _dictation;
    if (!mounted || dictation == null) return;
    final said = dictation.text;
    if (said.isNotEmpty) {
      final joined = [_before, said].where((s) => s.isNotEmpty).join(_before.endsWith('\n') ? '' : ' ');
      if (joined != _text.text) {
        _text.value = TextEditingValue(text: joined, selection: TextSelection.collapsed(offset: joined.length));
      }
    }
    setState(() {});
  }

  Future<void> _toggleMic() async {
    final current = _dictation;
    if (current != null && current.listening) return current.stop();
    if (current != null && current.finishing) return;
    FocusScope.of(context).unfocus();
    final store = AppScope.of(context).store;
    var next = await dictationFor(store);
    if (next == null) {
      // Nothing to listen with yet: choose an engine first.
      if (!mounted) return;
      await showVoiceSettings(context);
      next = await dictationFor(store);
      if (next == null) return;
    }
    if (!mounted) return next.dispose();
    if (current != null && current.setup == next.setup) {
      next.dispose();
      next = current;
    } else {
      current
        ?..removeListener(_heard)
        ..dispose();
      _dictation = next..addListener(_heard);
    }
    _before = _text.text.trimRight();
    await next.start();
  }

  Future<void> _save() async {
    await _dictation?.stop();
    final body = _text.text.trim();
    if (body.isEmpty || !mounted) return;
    AppScope.of(context).change((s) => s.addDiary(body, taskId: widget.taskId, habitId: widget.habitId));
    _text.clear();
    _before = '';
    FocusScope.of(context).unfocus();
    widget.onSaved?.call();
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final dictation = _dictation;
    final listening = dictation?.listening ?? false;
    final finishing = dictation?.finishing ?? false;
    final status = dictation?.status;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 12,
      children: [
        if (widget.about != null)
          Text(
            'About: ${widget.about}',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: text.labelLarge?.copyWith(color: AppColors.lavender, fontWeight: FontWeight.w700),
          ),
        TextField(
          key: const ValueKey('diary-draft'),
          controller: _text,
          autofocus: widget.autofocus,
          minLines: 3,
          maxLines: 8,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(hintText: 'An idea, a decision, how it went. Anything.'),
        ),
        if (dictation?.problem case final problem?)
          Text(problem, style: text.bodySmall?.copyWith(color: AppColors.red))
        else if (status != null)
          Text(status, style: text.bodySmall?.copyWith(color: AppColors.muted)),
        Row(
          spacing: 12,
          children: [
            if (voiceSupported)
              FilledButton.tonalIcon(
                key: const ValueKey('diary-mic'),
                style: listening
                    ? FilledButton.styleFrom(backgroundColor: AppColors.orange, foregroundColor: Colors.white)
                    : null,
                onPressed: finishing ? null : _toggleMic,
                icon: Icon(listening ? Icons.stop_rounded : Icons.mic_rounded),
                label: Text(listening ? 'Stop' : 'Speak'),
              ),
            const Spacer(),
            FilledButton(
              key: const ValueKey('diary-save'),
              onPressed: _save,
              child: const Text('Save'),
            ),
          ],
        ),
      ],
    );
  }
}

/// One entry: when it was logged, who wrote it, what it is about, the text.
class DiaryEntryCard extends StatelessWidget {
  const DiaryEntryCard(this.entry, {super.key, this.showAbout = true});

  final DiaryEntry entry;

  /// Off where the list is already about one task.
  final bool showAbout;

  Future<void> _edit(BuildContext context, AppState app) async {
    final controller = TextEditingController(text: entry.body);
    final body = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('${prettyDate(entry.date)}, ${hm(entry.createdAt)}'),
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
    if (body != null && body.trim().isNotEmpty) app.change((s) => s.updateDiary(entry.id, body));
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final text = Theme.of(context).textTheme;
    final mine = entry.author == DiaryEntry.me;
    final about = showAbout ? entry.about : null;
    return Card(
      color: mine ? null : AppColors.lavender.withValues(alpha: 0.14),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 6, 4, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  hm(entry.createdAt),
                  style: text.labelLarge?.copyWith(
                    color: AppColors.muted,
                    fontWeight: FontWeight.w700,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
                if (!mine) ...[
                  const SizedBox(width: 8),
                  Text(
                    'Claude',
                    style: text.labelLarge?.copyWith(color: AppColors.lavender, fontWeight: FontWeight.w700),
                  ),
                ],
                const Spacer(),
                PopupMenuButton<String>(
                  tooltip: 'More',
                  icon: const Icon(Icons.more_vert, size: 20, color: AppColors.muted),
                  onSelected: (v) => v == 'edit' ? _edit(context, app) : app.change((s) => s.deleteDiary(entry.id)),
                  itemBuilder: (context) => [
                    if (mine) const PopupMenuItem(value: 'edit', child: Text('Edit')),
                    const PopupMenuItem(value: 'delete', child: Text('Delete')),
                  ],
                ),
              ],
            ),
            if (about != null)
              Padding(
                padding: const EdgeInsets.only(right: 12, bottom: 6),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(color: AppColors.raised, borderRadius: BorderRadius.circular(10)),
                  child: Text(
                    about,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: text.labelMedium?.copyWith(color: AppColors.ink),
                  ),
                ),
              ),
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: SelectableText(entry.body, style: text.bodyMedium),
            ),
          ],
        ),
      ),
    );
  }
}

/// The diary: write or speak an entry at any time, and read back every day.
class DiaryPage extends StatelessWidget {
  const DiaryPage({super.key});

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final text = Theme.of(context).textTheme;
    final now = today();
    final entries = app.store.diary(from: addDays(now, -90));

    final children = <Widget>[
      const Card(
        child: Padding(padding: EdgeInsets.all(16), child: DiaryComposer()),
      ),
      if (entries.isEmpty)
        Padding(
          padding: const EdgeInsets.only(top: 32),
          child: Text(
            'Nothing written yet. Log anything, any time: it is kept by day, with the time you wrote it.',
            textAlign: TextAlign.center,
            style: text.bodyMedium?.copyWith(color: AppColors.muted),
          ),
        ),
    ];

    String? day;
    for (final e in entries) {
      if (e.date != day) {
        day = e.date;
        children.add(Padding(
          padding: const EdgeInsets.fromLTRB(4, 20, 4, 8),
          child: Text(
            e.date == now
                ? 'Today'
                : e.date == addDays(now, -1)
                    ? 'Yesterday'
                    : prettyDate(e.date),
            style: text.titleSmall,
          ),
        ));
      }
      children
        ..add(DiaryEntryCard(e))
        ..add(const SizedBox(height: 8));
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Diary'),
        actions: [
          if (voiceSupported)
            IconButton(
              key: const ValueKey('voice-settings'),
              tooltip: 'Voice',
              icon: const Icon(Icons.settings_voice_rounded),
              onPressed: () => showVoiceSettings(context),
            ),
        ],
      ),
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
