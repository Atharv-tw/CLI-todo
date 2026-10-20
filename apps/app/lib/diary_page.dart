import 'package:flutter/material.dart';
import 'package:vault_core/vault_core.dart';

import 'state.dart';
import 'task_widgets.dart';
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

  /// Fits what is spoken around what is typed, so an edit made while the mic
  /// is on stays made.
  final _draft = SpokenDraft();

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
    final next = _draft.merge(_text.text, dictation.text);
    if (next != null) {
      // The cursor follows the speech, unless the user has put it somewhere
      // to edit: then it stays where they are working.
      final at = _text.selection;
      final following = !at.isValid || at.end >= _text.text.length;
      _text.value = TextEditingValue(
        text: next,
        selection: following
            ? TextSelection.collapsed(offset: next.length)
            : TextSelection(
                baseOffset: at.baseOffset.clamp(0, next.length),
                extentOffset: at.extentOffset.clamp(0, next.length),
              ),
      );
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
    _draft.begin(_text.text);
    await next.start();
  }

  Future<void> _save() async {
    await _dictation?.stop();
    final body = _text.text.trim();
    if (body.isEmpty || !mounted) return;
    AppScope.of(context).change((s) => s.addDiary(body, taskId: widget.taskId, habitId: widget.habitId));
    _text.clear();
    _draft.begin('');
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
      spacing: 8,
      children: [
        if (widget.about != null)
          Text(
            'About: ${widget.about}',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: text.labelLarge?.copyWith(color: AppColors.lavender, fontWeight: FontWeight.w700),
          ),
        if (dictation?.problem case final problem?)
          Text(problem, style: text.bodySmall?.copyWith(color: AppColors.red))
        else if (status != null)
          Text(status, style: text.bodySmall?.copyWith(color: AppColors.muted)),
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          spacing: 8,
          children: [
            Expanded(
              child: TextField(
                key: const ValueKey('diary-draft'),
                controller: _text,
                autofocus: widget.autofocus,
                minLines: 1,
                maxLines: 6,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(hintText: 'Write or speak an entry'),
              ),
            ),
            if (voiceSupported)
              IconButton.filledTonal(
                key: const ValueKey('diary-mic'),
                tooltip: listening ? 'Stop listening' : 'Speak',
                style: listening
                    ? IconButton.styleFrom(backgroundColor: AppColors.orange, foregroundColor: Colors.white)
                    : null,
                onPressed: finishing ? null : _toggleMic,
                icon: Icon(listening ? Icons.stop_rounded : Icons.mic_rounded),
              ),
            IconButton.filled(
              key: const ValueKey('diary-save'),
              tooltip: 'Save',
              onPressed: _save,
              icon: const Icon(Icons.arrow_upward_rounded),
            ),
          ],
        ),
      ],
    );
  }
}

/// One entry: when it was logged, who wrote it, what it is about, the text.
class DiaryEntryCard extends StatelessWidget {
  const DiaryEntryCard(this.entry, {super.key, this.showAbout = true, this.showTime = true});

  final DiaryEntry entry;

  /// Off where the time is shown beside the card, as in the diary's timeline.
  final bool showTime;

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
    final header = [
      if (showTime)
        Text(
          hm(entry.createdAt),
          style: text.labelLarge?.copyWith(
            color: AppColors.muted,
            fontWeight: FontWeight.w700,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      if (!mine)
        Text(
          'Your agent',
          style: text.labelLarge?.copyWith(color: AppColors.lavender, fontWeight: FontWeight.w700),
        ),
    ];
    return Card(
      color: mine ? null : AppColors.lavender.withValues(alpha: 0.14),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 0, 14),
        // The menu sits in the corner, so an entry with nothing above its
        // words starts with them.
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  spacing: 6,
                  children: [
                    if (header.isNotEmpty) Row(spacing: 8, children: header),
                    if (about != null)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(color: AppColors.raised, borderRadius: BorderRadius.circular(10)),
                        child: Text(
                          about,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: text.labelMedium?.copyWith(color: AppColors.ink),
                        ),
                      ),
                    SelectableText(entry.body, style: text.bodyMedium),
                    // What Vault did with it, once the nightly run has been through.
                    if (entry.outcome case final outcome? when mine)
                      Padding(
                        key: ValueKey('outcome-${entry.id}'),
                        padding: const EdgeInsets.only(top: 2),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          spacing: 6,
                          children: [
                            const Padding(
                              padding: EdgeInsets.only(top: 2),
                              child: Icon(Icons.auto_awesome_rounded, size: 14, color: AppColors.lavender),
                            ),
                            Expanded(
                              child: Text(
                                outcome,
                                style: text.bodySmall?.copyWith(color: AppColors.lavender, height: 1.35),
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ),
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
      ),
    );
  }
}

/// Opens the diary box from anywhere (the + in the middle of the bar): write
/// or say anything; a task can be added from here instead.
Future<void> showQuickLog(BuildContext context, {String? date}) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  showDragHandle: true,
  builder: (sheet) => AppScope(
    state: AppScope.of(context),
    child: Padding(
      key: const ValueKey('quick-log-bar'),
      padding: EdgeInsets.fromLTRB(16, 0, 16, 16 + MediaQuery.viewInsetsOf(sheet).bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'What is on your mind?',
                  style: Theme.of(sheet).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
                ),
              ),
              TextButton.icon(
                key: const ValueKey('quick-log-task'),
                icon: const Icon(Icons.add_task_rounded, size: 18),
                label: const Text('A task instead'),
                onPressed: () {
                  Navigator.pop(sheet);
                  showTaskSheet(context, date: date ?? today());
                },
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Text(
              'Anything: what you did, what you have to do, an idea, how it went. '
              'Tonight it is filed into your notes and your plan.',
              style: Theme.of(sheet).textTheme.bodySmall?.copyWith(color: AppColors.muted),
            ),
          ),
          DiaryComposer(
            autofocus: true,
            onSaved: () {
              Navigator.pop(sheet);
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Saved to the diary')));
            },
          ),
        ],
      ),
    ),
  ),
);

/// Which entries the diary shows.
enum _Who { all, mine, agent }

/// The diary, as a tab: how much you have written, today's entries on a
/// timeline, and each earlier day folded into one tile, ten days at a time.
/// Entries are written from the + in the middle of the bar.
class DiaryPage extends StatefulWidget {
  const DiaryPage({super.key});

  @override
  State<DiaryPage> createState() => _DiaryPageState();
}

class _DiaryPageState extends State<DiaryPage> {
  static const _step = 10;

  /// How many earlier days are listed.
  int _shown = _step;

  /// The earlier days that have been opened.
  final _open = <String>{};

  _Who _who = _Who.all;

  bool _keep(DiaryEntry e) => switch (_who) {
    _Who.all => true,
    _Who.mine => e.author == DiaryEntry.me,
    _Who.agent => e.author != DiaryEntry.me,
  };

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final text = Theme.of(context).textTheme;
    final now = today();
    final all = app.store.diary();

    // Newest day first; within a day, in the order written.
    final byDay = <String, List<DiaryEntry>>{};
    for (final e in all.where(_keep)) {
      byDay.putIfAbsent(e.date, () => []).add(e);
    }
    final todays = [
      for (final day in byDay.keys.toList().reversed)
        if (day.compareTo(now) >= 0) ...byDay[day]!,
    ];
    final earlier = [
      for (final day in byDay.keys)
        if (day.compareTo(now) < 0) day,
    ];

    // How much you have written: today, this week, and days in a row.
    final mine = all.where((e) => e.author == DiaryEntry.me).toList();
    final days = {for (final e in mine) e.date};
    var streak = 0;
    for (var d = days.contains(now) ? now : addDays(now, -1); days.contains(d); d = addDays(d, -1)) {
      streak++;
    }
    final week = mine.where((e) => e.date.compareTo(addDays(now, -6)) >= 0).length;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 96),
      children: [
        Row(
          spacing: 8,
          children: [
            _Stat(key: const ValueKey('diary-stat-today'), value: '${mine.where((e) => e.date == now).length}', label: 'today'),
            _Stat(value: '$week', label: 'this week'),
            _Stat(value: '$streak', label: streak == 1 ? 'day in a row' : 'days in a row', hot: streak >= 3),
          ],
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          children: [
            for (final (who, label) in [(_Who.all, 'All'), (_Who.mine, 'Mine'), (_Who.agent, 'From your agent')])
              ChoiceChip(
                key: ValueKey('diary-filter-${who.name}'),
                label: Text(label),
                selected: _who == who,
                onSelected: (_) => setState(() => _who = who),
              ),
          ],
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 18, 4, 10),
          child: Row(
            children: [
              Expanded(child: Text('Today', style: text.titleLarge?.copyWith(fontWeight: FontWeight.w800))),
              Text(prettyDate(now), style: text.labelLarge?.copyWith(color: AppColors.muted)),
            ],
          ),
        ),
        if (todays.isEmpty)
          Card(
            color: AppColors.orange.withValues(alpha: 0.10),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                spacing: 12,
                children: [
                  const Icon(Icons.mic_rounded, color: AppColors.orange),
                  Expanded(
                    child: Text(
                      'Nothing written today. Tap + to say or write anything: it is kept with the time you wrote it.',
                      style: text.bodyMedium?.copyWith(height: 1.4),
                    ),
                  ),
                ],
              ),
            ),
          ),
        for (final (i, e) in todays.indexed) _TimelineEntry(e, last: i == todays.length - 1),
        if (earlier.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 22, 4, 10),
            child: Text('Earlier', style: text.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
          ),
        for (final day in earlier.take(_shown)) ...[
          _DayTile(
            key: ValueKey('diary-day-$day'),
            day: day,
            label: day == addDays(now, -1) ? 'Yesterday' : prettyDate(day),
            entries: byDay[day]!,
            open: _open.contains(day),
            onTap: () => setState(() => _open.contains(day) ? _open.remove(day) : _open.add(day)),
          ),
          if (_open.contains(day))
            for (final (i, e) in byDay[day]!.indexed) _TimelineEntry(e, last: i == byDay[day]!.length - 1),
        ],
        if (earlier.length > _shown)
          Align(
            child: TextButton(
              key: const ValueKey('diary-more'),
              onPressed: () => setState(() => _shown += _step),
              child: Text(switch ((earlier.length - _shown).clamp(1, _step)) {
                1 => 'Show 1 more day',
                final n => 'Show $n more days',
              }),
            ),
          ),
      ],
    );
  }
}

/// A number and what it counts, at the top of the diary.
class _Stat extends StatelessWidget {
  const _Stat({super.key, required this.value, required this.label, this.hot = false});

  final String value;
  final String label;
  final bool hot;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Expanded(
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
        decoration: BoxDecoration(
          color: hot ? AppColors.orange.withValues(alpha: 0.16) : AppColors.card,
          borderRadius: BorderRadius.circular(18),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              value,
              style: t.headlineSmall?.copyWith(
                fontWeight: FontWeight.w900,
                color: hot ? AppColors.orange : AppColors.ink,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
            Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: t.labelMedium?.copyWith(color: AppColors.muted)),
          ],
        ),
      ),
    );
  }
}

/// One entry on the day's timeline: its time and a dot on the left, the card
/// on the right.
class _TimelineEntry extends StatelessWidget {
  const _TimelineEntry(this.entry, {required this.last});

  final DiaryEntry entry;
  final bool last;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final mine = entry.author == DiaryEntry.me;
    final dot = mine ? AppColors.orange : AppColors.lavender;
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 46,
            child: Padding(
              padding: const EdgeInsets.only(top: 14),
              child: Text(
                hm(entry.createdAt),
                style: t.labelLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: mine ? AppColors.ink : AppColors.lavender,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),
          ),
          SizedBox(
            width: 18,
            child: Column(
              children: [
                const SizedBox(height: 17),
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: dot,
                    shape: BoxShape.circle,
                    boxShadow: [BoxShadow(color: dot.withValues(alpha: 0.5), blurRadius: 8)],
                  ),
                ),
                if (!last) Expanded(child: Container(width: 2, color: AppColors.line)),
              ],
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: DiaryEntryCard(entry, showTime: false),
            ),
          ),
        ],
      ),
    );
  }
}

/// A day that is over, folded into one tile: the date, how much was
/// written, and how it began. Tapping it shows the entries beneath.
class _DayTile extends StatelessWidget {
  const _DayTile({
    super.key,
    required this.day,
    required this.label,
    required this.entries,
    required this.open,
    required this.onTap,
  });

  final String day;
  final String label;
  final List<DiaryEntry> entries;
  final bool open;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final date = DateTime.parse(day);
    const weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    // What the person wrote says more about the day than the agent's note.
    final first = entries.firstWhere((e) => e.author == DiaryEntry.me, orElse: () => entries.first);
    final filed = entries.where((e) => e.outcome != null).length;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 8, 12),
            child: Row(
              spacing: 12,
              children: [
                Container(
                  width: 48,
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  decoration: BoxDecoration(color: AppColors.raised, borderRadius: BorderRadius.circular(14)),
                  child: Column(
                    children: [
                      Text(
                        '${date.day}',
                        style: text.titleLarge?.copyWith(fontWeight: FontWeight.w900, height: 1.1),
                      ),
                      Text(weekdays[date.weekday - 1], style: text.labelSmall?.copyWith(color: AppColors.muted)),
                    ],
                  ),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    spacing: 2,
                    children: [
                      Row(
                        spacing: 8,
                        children: [
                          Flexible(child: Text(label, style: text.titleSmall, overflow: TextOverflow.ellipsis)),
                          Text(
                            entries.length == 1 ? '1 entry' : '${entries.length} entries',
                            style: text.labelMedium?.copyWith(color: AppColors.muted),
                          ),
                          if (filed > 0)
                            const Icon(Icons.auto_awesome_rounded, size: 13, color: AppColors.lavender),
                        ],
                      ),
                      if (!open)
                        Text(
                          first.body.replaceAll('\n', ' '),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: text.bodySmall?.copyWith(color: AppColors.muted),
                        ),
                    ],
                  ),
                ),
                Icon(open ? Icons.expand_less_rounded : Icons.expand_more_rounded, color: AppColors.muted),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
