import 'dart:io';

import 'package:path/path.dart' as p;

/// One thing `myvault notes lint` found. An error is something that breaks the
/// vault's rules (a link to a note that does not exist, a link into `raw/`);
/// a warning is upkeep an agent or the person should look at.
class LintIssue {
  const LintIssue(this.level, this.code, this.file, this.message);

  /// `error` or `warning`.
  final String level;

  /// Short name of the check, such as `broken_link` or `not_in_index`.
  final String code;

  /// The note the issue is in, relative to the vault.
  final String file;
  final String message;

  bool get isError => level == 'error';

  Map<String, Object?> toJson() => {'level': level, 'code': code, 'file': file, 'message': message};
}

/// The operations a `log.md` line may name.
const logOps = {'ingest', 'work', 'query', 'lint', 'fix', 'setup'};

final _link = RegExp(r'!?\[\[([^\]|#]+)(?:#[^\]|]*)?(?:\|[^\]]*)?\]\]');
final _fence = RegExp(r'^```.*?^```', multiLine: true, dotAll: true);
final _inlineCode = RegExp(r'`[^`\n]*`');
final _logLine = RegExp(r'^- \[\d{4}-\d{2}-\d{2}\] (\w+) \| \S');
final _frontmatter = RegExp(r'^---\n(.*?)\n---\n', dotAll: true);

/// Checks a vault against the rules its README sets out: links resolve,
/// nothing links into `raw/`, every main note is in `INDEX.md` and linked
/// from somewhere, wiki pages carry frontmatter, each diary day in `raw/`
/// has its summary in `days/`, and `log.md` keeps its format. [today] is
/// the date staleness is measured against.
List<LintIssue> lintVault(String root, {DateTime? today}) {
  today ??= DateTime.now();
  final issues = <LintIssue>[];
  final notes = <String, String>{}; // relative path -> text
  for (final f in Directory(root).listSync(recursive: true).whereType<File>()) {
    final rel = p.relative(f.path, from: root).replaceAll(r'\', '/');
    if (!rel.endsWith('.md') || rel.split('/').any((part) => part.startsWith('.'))) continue;
    notes[rel] = f.readAsStringSync();
  }

  // Obsidian resolves [[name]] by file name anywhere, [[a/b]] by path.
  final byName = <String, List<String>>{};
  for (final rel in notes.keys) {
    byName.putIfAbsent(p.basenameWithoutExtension(rel).toLowerCase(), () => []).add(rel);
  }
  String? resolve(String target) {
    final t = target.trim();
    if (t.contains('/')) {
      final withExt = t.endsWith('.md') ? t : '$t.md';
      final hit = notes.keys.where((k) => k.toLowerCase() == withExt.toLowerCase());
      if (hit.isNotEmpty) return hit.first;
      return File(p.join(root, t)).existsSync() ? t : null;
    }
    final hits = byName[p.basenameWithoutExtension(t).toLowerCase()];
    if (hits != null) return hits.first;
    return File(p.join(root, t)).existsSync() ? t : null;
  }

  final inbound = <String, Set<String>>{};
  final indexed = <String>{};
  for (final MapEntry(key: rel, value: text) in notes.entries) {
    if (rel.startsWith('raw/')) continue;
    final body = text.replaceAll(_fence, '').replaceAll(_inlineCode, '');
    for (final m in _link.allMatches(body)) {
      final target = m.group(1)!.trim();
      if (target.toLowerCase().startsWith('raw/')) {
        issues.add(
          LintIssue('error', 'raw_link', rel, 'Links into raw/ ([[$target]]); only filing agents read the diary.'),
        );
        continue;
      }
      final hit = resolve(target);
      if (hit == null) {
        issues.add(LintIssue('error', 'broken_link', rel, 'Links to [[$target]], which does not exist.'));
        continue;
      }
      if (hit != rel) inbound.putIfAbsent(hit, () => {}).add(rel);
      if (rel == 'INDEX.md') indexed.add(hit);
    }
  }

  bool isWiki(String rel) =>
      rel.startsWith('people/') ||
      rel.startsWith('projects/') ||
      rel.startsWith('learning/') ||
      rel.startsWith('notes/');

  bool isMain(String rel) {
    final parts = rel.split('/');
    if (rel.startsWith('people/') || rel.startsWith('notes/')) return parts.length == 2;
    // A project's or a learning area's own page: projects/X/X.md.
    if (rel.startsWith('projects/') || rel.startsWith('learning/')) {
      return parts.length == 3 && p.basenameWithoutExtension(parts[2]) == parts[1];
    }
    return false;
  }

  for (final rel in notes.keys.toList()..sort()) {
    if (!isWiki(rel)) continue;
    if (isMain(rel) && notes.containsKey('INDEX.md') && !indexed.contains(rel)) {
      issues.add(LintIssue('warning', 'not_in_index', rel, 'Not listed in INDEX.md.'));
    }
    if ((inbound[rel] ?? const {}).isEmpty) {
      issues.add(LintIssue('warning', 'orphan', rel, 'No other note links here.'));
    }
    final parts = rel.split('/');
    final needsFrontmatter = isMain(rel) || (rel.startsWith('learning/') && parts.length == 3);
    if (!needsFrontmatter) continue;
    final fm = _frontmatter.firstMatch(notes[rel]!);
    if (fm == null) {
      issues.add(LintIssue('warning', 'no_frontmatter', rel, 'Has no frontmatter (type, updated).'));
      continue;
    }
    final fields = {
      for (final line in fm.group(1)!.split('\n'))
        if (line.contains(':')) line.split(':').first.trim(): line.split(':').skip(1).join(':').split('#').first.trim(),
    };
    for (final key in ['type', 'updated']) {
      if ((fields[key] ?? '').isEmpty) {
        issues.add(LintIssue('warning', 'no_frontmatter', rel, 'Frontmatter has no "$key".'));
      }
    }
    final updated = DateTime.tryParse(fields['updated'] ?? '');
    if (fields['type'] == 'project' && fields['status'] == 'building' && updated != null) {
      final days = today.difference(updated).inDays;
      if (days > 30) {
        issues.add(LintIssue('warning', 'stale', rel, 'Marked building, but not updated for $days days.'));
      }
    }
  }

  final rawDays = {
    for (final rel in notes.keys)
      if (rel.startsWith('raw/') && rel.split('/').length == 2) p.basenameWithoutExtension(rel),
  };
  final dayNotes = {
    for (final rel in notes.keys)
      if (rel.startsWith('days/') && rel.split('/').length == 2) p.basenameWithoutExtension(rel),
  };
  for (final d in rawDays.difference(dayNotes).toList()..sort()) {
    issues.add(LintIssue('warning', 'day_not_written', 'raw/$d.md', 'The diary for $d has no summary in days/.'));
  }
  for (final d in dayNotes.difference(rawDays).toList()..sort()) {
    issues.add(LintIssue('warning', 'day_without_raw', 'days/$d.md', 'There is no raw diary for $d.'));
  }

  final log = notes['log.md'];
  if (log != null) {
    for (final (i, line) in log.split('\n').indexed) {
      if (!line.startsWith('- ')) continue;
      final m = _logLine.firstMatch(line);
      if (m == null || !logOps.contains(m.group(1))) {
        issues.add(
          LintIssue(
            'warning',
            'log_format',
            'log.md',
            'Line ${i + 1} is not "- [YYYY-MM-DD] op | text" with op one of ${logOps.join(', ')}.',
          ),
        );
      }
    }
  }

  issues.sort((a, b) => a.isError == b.isError ? a.file.compareTo(b.file) : (a.isError ? -1 : 1));
  return issues;
}
