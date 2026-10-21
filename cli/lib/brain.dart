import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:vault_core/vault_core.dart';

/// One place a search found the words: a note in the vault, a diary entry or
/// a task.
class SearchHit {
  const SearchHit(this.kind, this.where, this.text, this.score, {this.line});

  /// `note`, `diary` or `task`.
  final String kind;

  /// A note's path in the vault, a diary entry's date and time, or a task's
  /// short id.
  final String where;
  final String text;
  final int score;
  final int? line;

  Map<String, Object?> toJson() => {'kind': kind, 'where': where, 'line': line, 'text': text, 'score': score};
}

List<String> _terms(String query) => query
    .toLowerCase()
    .split(RegExp(r'\s+'))
    .where((t) => t.length > 1 || RegExp(r'\d').hasMatch(t))
    .toList();

int _score(String text, List<String> terms) {
  final lower = text.toLowerCase();
  var score = 0;
  for (final t in terms) {
    if (!lower.contains(t)) return 0;
    score += t.allMatches(lower).length;
  }
  return score;
}

/// Finds [query] (every word must appear) in the vault's notes, the diary
/// and the tasks, best matches first. Never looks inside the vault's `raw/`,
/// the word-for-word diary that only filing agents read.
List<SearchHit> search(Store store, String? vault, String query, {Set<String>? kinds, int limit = 20}) {
  final terms = _terms(query);
  if (terms.isEmpty) return const [];
  bool want(String k) => kinds == null || kinds.isEmpty || kinds.contains(k);
  final hits = <SearchHit>[];

  if (want('note') && vault != null && Directory(vault).existsSync()) {
    for (final f in Directory(vault).listSync(recursive: true).whereType<File>()) {
      final rel = p.relative(f.path, from: vault).replaceAll(r'\', '/');
      if (!rel.endsWith('.md') || rel.startsWith('raw/') || rel.split('/').any((s) => s.startsWith('.'))) {
        continue;
      }
      final lines = f.readAsLinesSync();
      // A note scores as a whole (so a word in the title and another in the
      // body still match) and is shown by its best line.
      final whole = _score('$rel\n${lines.join('\n')}', terms);
      if (whole == 0) continue;
      var best = 0, bestScore = -1;
      for (final (i, line) in lines.indexed) {
        final s = terms.where((t) => line.toLowerCase().contains(t)).length;
        if (s > bestScore) (best, bestScore) = (i, s);
      }
      final titleBonus = _score(rel, terms) > 0 ? 5 : 0;
      hits.add(
        SearchHit('note', rel, lines.isEmpty ? '' : lines[best].trim(), whole + titleBonus, line: best + 1),
      );
    }
  }
  if (want('diary')) {
    for (final e in store.diary(author: DiaryEntry.me)) {
      final s = _score(e.body, terms);
      if (s > 0) {
        hits.add(SearchHit('diary', '${e.date} ${hm(e.createdAt)}', e.body.replaceAll('\n', ' '), s));
      }
    }
  }
  if (want('task')) {
    for (final t in store.tasks(undated: true)) {
      final s = _score('${t.title}\n${t.notes ?? ''}\n${t.list ?? ''}', terms);
      if (s > 0) hits.add(SearchHit('task', t.id.substring(0, 6), '${t.done ? '[x]' : '[ ]'} ${t.title}', s));
    }
  }
  hits.sort((a, b) => b.score.compareTo(a.score));
  return hits.take(limit).toList();
}

String _today() => today();

/// The vault's folder, or an error that says how to make one.
String requireVault(String? path) {
  if (path == null || !Directory(path).existsSync()) {
    throw TodoException('No vault on this device. Create one with: myvault notes init');
  }
  return path;
}

/// A file name that is safe on every system, keeping the title readable.
String fileTitle(String title) {
  final t = title
      .trim()
      .replaceAll(RegExp(r'[\\/:*?"<>|#^\[\]]'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  if (t.isEmpty) throw TodoException('Give a title.');
  return t;
}

/// Appends a line to the vault's `log.md` in its format.
void appendLog(String vault, String op, String text) {
  final f = File(p.join(vault, 'log.md'));
  if (!f.existsSync()) {
    f.writeAsStringSync('# Log\n\nOne line per change to the vault, oldest first, appended at the end.\n\n');
  }
  final s = f.readAsStringSync();
  f.writeAsStringSync(
    '${s.endsWith('\n') ? s : '$s\n'}- [${_today()}] $op | ${text.replaceAll('\n', ' ')}\n',
  );
}

/// Adds [line] under the `## [section]` heading of the vault's `INDEX.md`
/// (making the heading if needed), unless a line naming [link] is there.
void addToIndex(String vault, String section, String link, String line) {
  final f = File(p.join(vault, 'INDEX.md'));
  var s = f.existsSync() ? f.readAsStringSync() : '# Index\n';
  if (s.contains('[[$link')) return;
  final heading = '## $section';
  final at = s.indexOf('\n$heading\n');
  if (at < 0) {
    s = '${s.trimRight()}\n\n$heading\n\n$line\n';
  } else {
    // After the last list line of that section.
    final start = at + heading.length + 2;
    final next = s.indexOf('\n## ', start);
    final end = next < 0 ? s.length : next;
    final body = s.substring(start, end).trimRight();
    s = '${s.substring(0, start)}${body.isEmpty ? '\n' : body}\n$line\n${next < 0 ? '' : s.substring(next)}';
  }
  f.writeAsStringSync(s);
}

String _frontmatter(Map<String, String> fields) =>
    '---\n${[for (final e in fields.entries) '${e.key}: ${e.value}'].join('\n')}\n---\n';

/// Writes a note worth keeping: `notes/<title>.md`, or inside a project's
/// folder when [project] is given. Lists it in `INDEX.md` and logs it.
/// Returns its path in the vault.
String newNote(String vault, String title, {String body = '', String? project, String? source}) {
  final name = fileTitle(title);
  final rel = project == null ? 'notes/$name.md' : 'projects/${projectFolder(vault, project)}/$name.md';
  final f = File(p.join(vault, rel));
  if (f.existsSync()) throw TodoException('$rel already exists.');
  f
    ..createSync(recursive: true)
    ..writeAsStringSync(
      '${_frontmatter({'type': source == null ? 'note' : 'source', 'updated': _today(), 'source': ?source})}'
      '# $name\n\n${body.trim()}${body.trim().isEmpty ? '' : '\n'}',
    );
  final link = rel.substring(0, rel.length - 3);
  if (project == null) addToIndex(vault, 'Notes', link, '- [[$link]]');
  appendLog(vault, 'query', '$name ($rel)');
  return rel;
}

/// The folder of the project called [name] (any case), or an error.
String projectFolder(String vault, String name) {
  final dir = Directory(p.join(vault, 'projects'));
  if (dir.existsSync()) {
    for (final d in dir.listSync().whereType<Directory>()) {
      if (p.basename(d.path).toLowerCase() == name.trim().toLowerCase()) return p.basename(d.path);
    }
  }
  throw TodoException('No project called "$name". See: myvault project list');
}

/// A project as `myvault project list` shows it.
class ProjectInfo {
  const ProjectInfo(this.name, this.status, this.updated, this.what);
  final String name;
  final String? status;
  final String? updated;

  /// The first sentence after "What it is", if there is one.
  final String? what;

  Map<String, Object?> toJson() => {'name': name, 'status': status, 'updated': updated, 'what': what};
}

Map<String, String> _fields(String text) {
  final m = RegExp(r'^---\n(.*?)\n---\n', dotAll: true).firstMatch(text);
  if (m == null) return const {};
  return {
    for (final line in m.group(1)!.split('\n'))
      if (line.contains(':'))
        line.split(':').first.trim(): line.split(':').skip(1).join(':').split('#').first.trim(),
  };
}

List<ProjectInfo> listProjects(String vault) {
  final dir = Directory(p.join(vault, 'projects'));
  if (!dir.existsSync()) return const [];
  final out = <ProjectInfo>[];
  for (final d in dir.listSync().whereType<Directory>()) {
    final name = p.basename(d.path);
    final f = File(p.join(d.path, '$name.md'));
    if (!f.existsSync()) continue;
    final text = f.readAsStringSync();
    final fields = _fields(text);
    final what = RegExp(r'\*\*What it is:\*\*\s*(.+?)(?:\.\s|\n\n)', dotAll: true).firstMatch(text)?.group(1);
    out.add(ProjectInfo(name, fields['status'], fields['updated'], what?.replaceAll('\n', ' ').trim()));
  }
  out.sort((a, b) => (b.updated ?? '').compareTo(a.updated ?? ''));
  return out;
}

/// Starts a project: `projects/<name>/` with its overview, `log.md` and
/// `info.md`, listed in `INDEX.md`. Returns the folder's path in the vault.
String newProject(String vault, String name, {String? what, String? repo, String status = 'building'}) {
  final folder = fileTitle(name);
  final dir = Directory(p.join(vault, 'projects', folder));
  if (dir.existsSync()) throw TodoException('projects/$folder already exists.');
  dir.createSync(recursive: true);
  final base = 'projects/$folder';
  File(p.join(dir.path, '$folder.md')).writeAsStringSync(
    '${_frontmatter({'type': 'project', 'status': status, 'updated': _today()})}'
    '# $folder\n\n**What it is:** ${what?.trim() ?? 'not written down yet.'}\n\n'
    '**Status:** started ${_today()}.\n\n'
    'Details: [[$base/info|info]]. Work log: [[$base/log|log]].\n',
  );
  File(
    p.join(dir.path, 'log.md'),
  ).writeAsStringSync('# $folder: log\n\nOldest first.\n\n- ${_today()}: Started.\n');
  File(p.join(dir.path, 'info.md')).writeAsStringSync(
    '# $folder: info\n\n- **Repo:** ${repo ?? 'none yet.'}\n- **Hosting:** none recorded.\n',
  );
  addToIndex(
    vault,
    'Projects',
    '$base/$folder',
    '- [[$base/$folder|$folder]]: ${what?.trim() ?? ''}'.trimRight(),
  );
  appendLog(vault, 'setup', 'new project $folder ($base/)');
  return base;
}

/// Adds a dated line to a project's work log (and a line to `log.md`).
String logProject(String vault, String name, String text, {String? ref}) {
  final folder = projectFolder(vault, name);
  final f = File(p.join(vault, 'projects', folder, 'log.md'));
  final s = f.existsSync() ? f.readAsStringSync() : '# $folder: log\n\nOldest first.\n\n';
  final line = '- ${_today()}: ${text.trim()}${ref == null ? '' : ' ($ref)'}';
  f.writeAsStringSync('${s.endsWith('\n') ? s : '$s\n'}$line\n');
  appendLog(vault, 'work', '$folder: ${text.trim()}');
  return 'projects/$folder/log.md';
}

const linkNote = 'CLAUDE.local.md';

/// Ties a code folder to a vault project: drops a local note there that
/// tells an agent working in it to log finished work to that project, kept
/// out of git, and records the folder in the project's `info.md`.
List<String> linkFolder(String vault, String folder, String project) {
  final name = projectFolder(vault, project);
  final dir = Directory(folder).absolute;
  if (!dir.existsSync()) throw TodoException('There is no folder at ${dir.path}');
  final lines = <String>[];
  final note = File(p.join(dir.path, linkNote));
  final text =
      '# Log this work to my vault\n\n'
      'This folder is my project "$name". When you finish a piece of work here (a\n'
      'feature or fix that works, a commit or merged pull request, a release, a\n'
      'deploy, a decision about where the project goes), log it: run\n'
      '`myvault project log "$name" "what was done" --ref "PR #12"`, then\n'
      '`myvault notes save`. Before the session ends, log anything not yet logged.\n\n'
      'For coding work, do not read my other notes, never open the vault\'s `raw/`,\n'
      'and never copy anything from the vault into this folder.\n';
  if (note.existsSync() && note.readAsStringSync().contains('Log this work to my vault')) {
    lines.add('${note.path} already links here.');
  } else {
    note.writeAsStringSync(note.existsSync() ? '${note.readAsStringSync()}\n$text' : text);
    lines.add('Wrote ${note.path}.');
  }
  final exclude = File(p.join(dir.path, '.git', 'info', 'exclude'));
  if (Directory(p.join(dir.path, '.git')).existsSync()) {
    exclude.createSync(recursive: true);
    final s = exclude.readAsStringSync();
    if (!s.split('\n').contains(linkNote)) {
      exclude.writeAsStringSync('${s.isEmpty || s.endsWith('\n') ? s : '$s\n'}$linkNote\n');
    }
    lines.add('Kept it out of git (.git/info/exclude).');
  }
  final info = File(p.join(vault, 'projects', name, 'info.md'));
  final s = info.existsSync() ? info.readAsStringSync() : '# $name: info\n';
  if (!s.contains(dir.path)) {
    info.writeAsStringSync('${s.trimRight()}\n- **Local folder:** `${dir.path}`\n');
  }
  return lines;
}

/// The goals in `Me.md`, one per bullet under `## Goals`.
List<String> goals(String vault) {
  final f = File(p.join(vault, 'Me.md'));
  if (!f.existsSync()) return const [];
  final s = f.readAsStringSync();
  final m = RegExp(r'^## Goals\s*\n(.*?)(?=^## |\z)', multiLine: true, dotAll: true).firstMatch(s);
  if (m == null) return const [];
  final out = <String>[];
  for (final line in m.group(1)!.split('\n')) {
    if (line.startsWith('- ')) {
      out.add(line.substring(2).trim());
    } else if (line.startsWith('  ') && out.isNotEmpty) {
      out[out.length - 1] = '${out.last} ${line.trim()}';
    }
  }
  return out.where((g) => !g.startsWith('(')).toList();
}

/// Adds a goal to `Me.md` with today's date.
void addGoal(String vault, String goal) {
  final f = File(p.join(vault, 'Me.md'));
  var s = f.existsSync() ? f.readAsStringSync() : '# Me\n';
  final line = '- ${goal.trim()} (${_today()}).';
  final m = RegExp(r'^## Goals\s*\n', multiLine: true).firstMatch(s);
  if (m == null) {
    s = '${s.trimRight()}\n\n## Goals\n\n$line\n';
  } else {
    final next = s.indexOf('\n## ', m.end);
    final end = next < 0 ? s.length : next;
    final body = s.substring(m.end, end).trimRight();
    s = '${s.substring(0, m.end)}${body.isEmpty ? '\n' : '$body\n'}$line\n${next < 0 ? '' : s.substring(next)}';
  }
  f.writeAsStringSync(s);
  appendLog(vault, 'ingest', 'goal added to Me.md: ${goal.trim()}');
}

/// The newest page in `morning/` or `weekly/` (or the one for [date]).
({String path, String text})? page(String vault, String kind, {String? date}) {
  final dir = Directory(p.join(vault, kind));
  if (!dir.existsSync()) return null;
  final files = dir.listSync().whereType<File>().where((f) => f.path.endsWith('.md')).toList()
    ..sort((a, b) => b.path.compareTo(a.path));
  final pick = date == null
      ? files.firstOrNull
      : files.where((f) => p.basenameWithoutExtension(f.path) == date).firstOrNull;
  if (pick == null) return null;
  return (path: p.relative(pick.path, from: vault), text: pick.readAsStringSync());
}

/// Reads a note by its path in the vault or its title, refusing `raw/`.
({String path, String text}) readNote(String vault, String ref) {
  final r = ref.trim().replaceAll(r'\', '/');
  if (r.toLowerCase().startsWith('raw/')) {
    throw TodoException(
      'raw/ is the word-for-word diary; only the filing agent reads it. See days/ instead.',
    );
  }
  final direct = File(p.join(vault, r.endsWith('.md') ? r : '$r.md'));
  if (direct.existsSync()) {
    return (path: p.relative(direct.path, from: vault), text: direct.readAsStringSync());
  }
  final want = p.basenameWithoutExtension(r).toLowerCase();
  for (final f in Directory(vault).listSync(recursive: true).whereType<File>()) {
    final rel = p.relative(f.path, from: vault).replaceAll(r'\', '/');
    if (rel.startsWith('raw/') || !rel.endsWith('.md') || rel.split('/').any((s) => s.startsWith('.'))) {
      continue;
    }
    if (p.basenameWithoutExtension(rel).toLowerCase() == want) return (path: rel, text: f.readAsStringSync());
  }
  throw TodoException('No note called "$ref". Try: myvault search $ref');
}

/// Commits everything in the vault and pushes it when it has a remote.
List<String> saveVault(String vault, {String? message}) {
  ProcessResult git(List<String> args) => Process.runSync('git', ['-C', vault, ...args]);
  try {
    if (!Directory(p.join(vault, '.git')).existsSync()) {
      return ['The vault is not a git repository; nothing to save.'];
    }
    git(['add', '-A']);
    if ((git(['status', '--porcelain']).stdout as String).trim().isEmpty) return ['Nothing new to save.'];
    final c = git(['commit', '-q', '-m', message ?? 'Notes: ${_today()}']);
    if (c.exitCode != 0) return ['git commit failed: ${(c.stderr as String).trim()}'];
    if (git(['remote', 'get-url', 'origin']).exitCode != 0) return ['Saved (no remote to push to).'];
    final push = git(['push', '-q']);
    if (push.exitCode == 0) return ['Saved and pushed.'];
    final pull = git(['pull', '-q', '--rebase']);
    if (pull.exitCode == 0 && git(['push', '-q']).exitCode == 0) return ['Saved and pushed (after pulling).'];
    return ['Saved here, but the push was refused: ${(push.stderr as String).trim()}'];
  } on ProcessException {
    return ['git is not installed.'];
  }
}

/// One line of `myvault doctor`.
class Check {
  const Check(this.ok, this.what, this.detail, {this.fix});
  final bool ok;
  final String what;
  final String detail;
  final String? fix;

  Map<String, Object?> toJson() => {'ok': ok, 'what': what, 'detail': detail, 'fix': fix};
}

/// True while `Me.md` is still the starter one (or missing), so setup may
/// write the answers about the user into it.
bool meIsBlank(String vault) {
  final f = File(p.join(vault, 'Me.md'));
  if (!f.existsSync()) return true;
  return f.readAsStringSync().contains('(What you are working towards. One line each.)');
}

/// Writes the user's answers from setup into `Me.md`.
void fillMe(String vault, {String? name, List<String> goals = const [], String? wake, String? sleep}) {
  String? clean(String? v) => v == null || v.trim().isEmpty ? null : v.trim();
  final lines = [
    '# Me',
    '',
    if (clean(name) != null) ...['Call me ${clean(name)}.', ''],
    '## Goals',
    '',
    if (goals.isEmpty) '- (What you are working towards. One line each.)',
    for (final g in goals)
      if (g.trim().isNotEmpty) '- ${g.trim()} (${_today()}).',
    '',
    '## How I like my day planned',
    '',
    '- Wake up: ${clean(wake) ?? ''}',
    '- Asleep by: ${clean(sleep) ?? ''}',
    '- Blocks, in the order I like them:',
    '- Never schedule:',
    '',
    '## Things the assistant should know',
    '',
    '- (Anything that helps it plan or file for you: who people are, what your',
    '  projects are called, words you use.)',
    '',
  ];
  File(p.join(vault, 'Me.md')).writeAsStringSync(lines.join('\n'));
  appendLog(vault, 'setup', 'Me.md filled in from setup');
}

/// The ISO week of [d], as 2026-W43.
String isoWeek(DateTime d) {
  final thursday = d.add(Duration(days: 4 - d.weekday));
  final week = ((thursday.difference(DateTime(thursday.year, 1, 1)).inDays) / 7).floor() + 1;
  return '${thursday.year}-W${week.toString().padLeft(2, '0')}';
}

String _withoutFrontmatter(String text) => text.replaceFirst(RegExp(r'^---\n.*?\n---\n', dotAll: true), '');

String? _heading(String text) => RegExp(r'^# (.+)$', multiLine: true).firstMatch(text)?.group(1)?.trim();

/// Copies what a device without the vault shows of it (the newest morning
/// and weekly pages, the goals, the projects) into the synced pages, so the
/// phone has them after the next sync. Returns how many pages changed.
/// Files what the phone asked for, since it cannot write the vault: goals
/// into `Me.md`, new projects into `projects/`. A request is removed once
/// filed; one already in the vault is just removed. Returns how many.
int fileRequests(Store store, String vault) {
  var filed = 0;
  for (final r in store.requests()) {
    final data = (jsonDecode(r.body) as Map).cast<String, Object?>();
    final text = (data['text'] as String? ?? '').trim();
    switch (r.title) {
      case 'goal':
        final known = goals(vault).map((g) => g.toLowerCase());
        if (text.isNotEmpty && !known.any((g) => g.startsWith(text.toLowerCase()))) addGoal(vault, text);
      case 'project':
        final known = listProjects(vault).map((x) => x.name.toLowerCase());
        if (text.isNotEmpty && !known.contains(fileTitle(text).toLowerCase())) {
          final what = (data['what'] as String?)?.trim();
          newProject(vault, text, what: what == null || what.isEmpty ? null : what);
        }
      default:
        continue; // from a newer app; leave it for a newer myvault
    }
    store.deletePage(r.id);
    filed++;
  }
  return filed;
}

int publishPages(Store store, String vault) {
  var changed = 0;
  for (final kind in ['morning', 'weekly']) {
    final dir = Directory(p.join(vault, kind));
    if (!dir.existsSync()) continue;
    final files = dir.listSync().whereType<File>().where((f) => f.path.endsWith('.md')).toList()
      ..sort((a, b) => b.path.compareTo(a.path));
    for (final f in files.take(kind == 'morning' ? 7 : 4)) {
      final text = _withoutFrontmatter(f.readAsStringSync()).trim();
      if (store.putPage(kind, p.basenameWithoutExtension(f.path), text, title: _heading(text))) changed++;
    }
  }
  if (store.putPage('goals', 'all', goals(vault).join('\n'), title: 'Goals')) changed++;
  final me = File(p.join(vault, 'Me.md'));
  if (me.existsSync() &&
      store.putPage('me', 'me', _withoutFrontmatter(me.readAsStringSync()).trim(), title: 'Me')) {
    changed++;
  }
  final projects = [
    for (final x in listProjects(vault))
      {
        ...x.toJson(),
        'overview': _withoutFrontmatter(
          File(p.join(vault, 'projects', x.name, '${x.name}.md')).readAsStringSync(),
        ).trim(),
      },
  ];
  if (store.putPage('projects', 'all', jsonEncode(projects), title: 'Projects')) changed++;
  return changed;
}
