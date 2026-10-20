import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:todo_cli/vault.dart';
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
    expect(readme, contains('Add, never rewrite'));
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
}
