import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:vault_cli/brain.dart';
import 'package:vault_cli/vault.dart';
import 'package:vault_cli/vault_lint.dart';
import 'package:vault_core/vault_core.dart';

void main() {
  late Directory dir;
  late Store store;
  late String vault;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('brain');
    vault = p.join(dir.path, 'Vault');
    scaffoldVault(vault);
    store = Store(openMemoryDb())..setMeta(vaultPathKey, vault);
  });
  tearDown(() => dir.deleteSync(recursive: true));

  String read(String rel) => File(p.join(vault, rel)).readAsStringSync();

  test('a note is saved with frontmatter, listed in INDEX and logged, and the vault stays healthy', () {
    final rel = newNote(vault, 'CS229 or Karpathy', body: 'Which course first. Karpathy.');
    expect(rel, 'notes/CS229 or Karpathy.md');
    expect(read(rel), startsWith('---\ntype: note\nupdated: '));
    expect(read('INDEX.md'), contains('- [[notes/CS229 or Karpathy]]'));
    expect(read('log.md'), contains('] query | CS229 or Karpathy'));
    expect(() => newNote(vault, 'CS229 or Karpathy'), throwsA(isA<TodoException>()));
    expect(lintVault(vault), isEmpty);
  });

  test('a project starts with its three notes, takes log lines, lists, and stays healthy', () {
    newProject(vault, 'Helios', what: 'Security scanning that ships fixes', repo: 'https://github.com/x/helios');
    expect(read('projects/Helios/Helios.md'), contains('type: project\nstatus: building'));
    expect(read('projects/Helios/info.md'), contains('https://github.com/x/helios'));
    expect(read('INDEX.md'), contains('[[projects/Helios/Helios|Helios]]: Security scanning that ships fixes'));

    logProject(vault, 'helios', 'Sessions and API tokens', ref: 'PR #12');
    expect(read('projects/Helios/log.md'), contains(': Sessions and API tokens (PR #12)'));
    expect(read('log.md'), contains('] work | Helios: Sessions and API tokens'));
    expect(() => logProject(vault, 'Nope', 'x'), throwsA(isA<TodoException>()));

    final list = listProjects(vault);
    expect(list.single.name, 'Helios');
    expect(list.single.status, 'building');
    expect(list.single.what, 'Security scanning that ships fixes');
    expect(lintVault(vault), isEmpty);
  });

  test('linking a code folder writes the local note, keeps it out of git and records the folder', () {
    newProject(vault, 'Helios');
    final code = Directory(p.join(dir.path, 'helios-code'))..createSync();
    Directory(p.join(code.path, '.git', 'info')).createSync(recursive: true);
    final lines = linkFolder(vault, code.path, 'Helios');
    expect(File(p.join(code.path, 'CLAUDE.local.md')).readAsStringSync(), contains('myvault project log "Helios"'));
    expect(File(p.join(code.path, '.git', 'info', 'exclude')).readAsStringSync(), contains('CLAUDE.local.md'));
    expect(read('projects/Helios/info.md'), contains(code.path));
    expect(lines.first, startsWith('Wrote'));
    expect(linkFolder(vault, code.path, 'Helios').first, contains('already links'));
  });

  test('search finds notes, diary and tasks, but never raw/', () {
    newNote(vault, 'Hash maps', body: 'Lookup in one step, by the key.');
    File(p.join(vault, 'raw', '2026-10-13.md')).writeAsStringSync('- 10:00 secret hash maps thought\n');
    store.addDiary('Finally got hash maps today');
    store.addTask(title: 'Revise hash maps');
    final hits = search(store, vault, 'hash maps');
    expect(hits.map((h) => h.kind).toSet(), {'note', 'diary', 'task'});
    expect(hits.where((h) => h.where.startsWith('raw/')), isEmpty);
    expect(hits.first.where, 'notes/Hash maps.md');
    expect(search(store, vault, 'hash maps', kinds: {'task'}).single.kind, 'task');
    expect(search(store, vault, 'zebra'), isEmpty);
  });

  test('notes are read by path or title; raw/ is refused', () {
    newNote(vault, 'Plan', body: 'The plan.');
    expect(readNote(vault, 'Plan').path, 'notes/Plan.md');
    expect(readNote(vault, 'notes/Plan').text, contains('The plan.'));
    expect(() => readNote(vault, 'raw/2026-10-13'), throwsA(isA<TodoException>()));
    expect(() => readNote(vault, 'Nothing'), throwsA(isA<TodoException>()));
  });

  test('setup fills Me.md once, and goals are read and added', () {
    expect(meIsBlank(vault), isTrue);
    expect(goals(vault), isEmpty);
    fillMe(vault, name: 'Sam', goals: ['Ship the thesis'], wake: '07:00', sleep: '23:00');
    expect(meIsBlank(vault), isFalse);
    expect(read('Me.md'), contains('Call me Sam.'));
    expect(read('Me.md'), contains('- Wake up: 07:00'));
    addGoal(vault, 'Run a 10k');
    expect(goals(vault), hasLength(2));
    expect(goals(vault).last, startsWith('Run a 10k'));
    expect(read('log.md'), contains('] ingest | goal added to Me.md: Run a 10k'));
  });

  test('the newest morning page, or one by date', () {
    expect(page(vault, 'morning'), isNull);
    File(p.join(vault, 'morning', '2026-10-20.md')).writeAsStringSync('# Tue\n');
    File(p.join(vault, 'morning', '2026-10-21.md')).writeAsStringSync('# Wed\n');
    expect(page(vault, 'morning')!.text, '# Wed\n');
    expect(page(vault, 'morning', date: '2026-10-20')!.path, 'morning/2026-10-20.md');
  });
}
