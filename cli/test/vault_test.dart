import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:todo_cli/vault.dart';
import 'package:todo_cli/vault_lint.dart';
import 'package:todo_core/todo_core.dart';

void main() {
  late Directory dir;
  late Store store;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('vault');
    store = Store(openMemoryDb());
  });
  tearDown(() => dir.deleteSync(recursive: true));

  test('a new vault gets the starter notes, and the rules an assistant files by', () {
    final written = scaffoldVault(dir.path);
    expect(written, containsAll(['README.md', 'INDEX.md', 'log.md', 'Me.md', 'Rules.md', 'Decisions.md', 'Ideas.md']));
    for (final folder in ['raw', 'days', 'people', 'projects', 'learning', 'morning', 'weekly']) {
      expect(Directory(p.join(dir.path, folder)).existsSync(), isTrue, reason: folder);
    }
    final readme = File(p.join(dir.path, 'README.md')).readAsStringSync();
    expect(readme, contains('Rules for filing'));
    expect(readme, contains('Never changed:'));
    expect(readme, contains('Every other agent stays out of `raw/`'));
  });

  test('setting up a vault again never touches a note that is there', () {
    scaffoldVault(dir.path);
    final me = File(p.join(dir.path, 'Me.md'))..writeAsStringSync('# Me\n\nMine.\n');
    File(p.join(dir.path, 'Ideas.md')).deleteSync();

    expect(scaffoldVault(dir.path), ['Ideas.md']);
    expect(me.readAsStringSync(), '# Me\n\nMine.\n');
  });

  test('status says where the vault is and how much of the diary waits', () {
    expect(vaultStatus(store), containsPair('path', null));

    scaffoldVault(dir.path);
    store.setMeta(vaultPathKey, dir.path);
    final mine = store.addDiary('Decided to park Onyx');
    store.addDiary('Parked it too');
    store.addDiary('Handled 2 entries', author: DiaryEntry.assistant);
    var status = vaultStatus(store);
    expect(status['path'], dir.path);
    expect(status['exists'], isTrue);
    expect(status['git'], isFalse);
    expect(status['unfiled'], 2); // the assistant's own notes are never filed

    store.markDiaryFiled([mine.id]);
    expect(vaultStatus(store)['unfiled'], 1);

    dir.deleteSync(recursive: true);
    status = vaultStatus(store);
    expect(status['exists'], isFalse);
    dir.createSync();
  });

  group('lint', () {
    void write(String rel, String text) => File(p.join(dir.path, rel))
      ..createSync(recursive: true)
      ..writeAsStringSync(text);
    List<String> codes() => [for (final i in lintVault(dir.path, today: DateTime(2026, 10, 20))) '${i.code} ${i.file}'];

    test('a new vault is healthy', () {
      scaffoldVault(dir.path);
      expect(lintVault(dir.path), isEmpty);
    });

    test('finds broken links and links into raw/, but not examples in code', () {
      scaffoldVault(dir.path);
      write(
        'notes/A.md',
        '---\ntype: note\nupdated: 2026-10-20\n---\n# A\n\nSee [[Nowhere]] and [[raw/2026-10-13|the diary]].\n'
            'In code: `[[Fine]]`.\n\n```\n[[Also fine]]\n```\n',
      );
      write(
        'INDEX.md',
        '# Index\n\n- [[notes/A]]\n- [[README]] [[log]] [[Rules]] [[Me]] [[Voice]] [[Decisions]] [[Ideas]]\n',
      );
      final issues = lintVault(dir.path);
      expect(issues.where((i) => i.isError).map((i) => i.code), containsAll(['broken_link', 'raw_link']));
      expect(issues.where((i) => i.isError), hasLength(2));
      expect(issues.first.isError, isTrue);
    });

    test('finds notes missing from INDEX, orphans, missing frontmatter and stale projects', () {
      scaffoldVault(dir.path);
      write(
        'projects/Onyx/Onyx.md',
        '---\ntype: project\nstatus: building\nupdated: 2026-08-01\n---\n# Onyx\n\n[[projects/Onyx/log|log]]\n',
      );
      write('projects/Onyx/log.md', '# Onyx: log\n');
      write('people/Sam.md', '# Sam\n');
      expect(
        codes(),
        containsAll([
          'not_in_index people/Sam.md',
          'orphan people/Sam.md',
          'no_frontmatter people/Sam.md',
          'not_in_index projects/Onyx/Onyx.md',
          'stale projects/Onyx/Onyx.md',
        ]),
      );
      expect(codes(), isNot(contains('orphan projects/Onyx/log.md')));
    });

    test('pairs raw/ days with days/ notes, and checks the log format', () {
      scaffoldVault(dir.path);
      write('raw/2026-10-13.md', '# Tue 13 Oct 2026\n');
      write('days/2026-10-14.md', '# Wed 14 Oct 2026\n');
      File(p.join(dir.path, 'log.md')).writeAsStringSync(
        '# Log\n\n- [2026-10-13] ingest | diary 13 Oct\n- 2026-10-14: old style\n- [2026-10-14] dance | wrong op\n',
      );
      final found = codes();
      expect(found, containsAll(['day_not_written raw/2026-10-13.md', 'day_without_raw days/2026-10-14.md']));
      expect(found.where((c) => c.startsWith('log_format')), hasLength(2));
    });
  });
}
