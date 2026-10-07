import 'package:test/test.dart';
import 'package:todo_core/todo_core.dart';

/// In-memory stand-in for the server: same contract as the Postgres trigger.
class FakeRemote implements Remote {
  final tables = <String, Map<String, Map<String, Object?>>>{};
  var _clock = 0;
  var failPush = false;

  @override
  Future<void> push(String table, List<Map<String, Object?>> rows) async {
    if (failPush) throw SyncException('offline');
    final stored = tables.putIfAbsent(table, () => {});
    for (final row in rows) {
      final old = stored[row['id']];
      if (old != null && (row['updated_at'] as String).compareTo(old['updated_at'] as String) < 0) continue;
      stored[row['id'] as String] = {...row, 'server_at': (++_clock).toString().padLeft(9, '0')};
    }
  }

  @override
  Future<List<Map<String, Object?>>> pull(String table, String? since) async {
    final rows = (tables[table] ?? {}).values
        .where((r) => since == null || (r['server_at'] as String).compareTo(since) > 0)
        .toList()
      ..sort((a, b) => (a['server_at'] as String).compareTo(b['server_at'] as String));
    return rows;
  }
}

void main() {
  late FakeRemote remote;
  late Store phone, laptop;
  late SyncEngine phoneSync, laptopSync;

  setUp(() {
    remote = FakeRemote();
    phone = Store(openMemoryDb());
    laptop = Store(openMemoryDb());
    phoneSync = SyncEngine(phone, remote);
    laptopSync = SyncEngine(laptop, remote);
  });

  Future<void> settle() => Future<void>.delayed(const Duration(milliseconds: 2));

  test('rows travel both ways, with their list', () async {
    final list = laptop.ensureList('Exams');
    final t = laptop.addTask(title: 'revise', date: '2026-10-04', startTime: '08:30', listId: list.id);
    phone.addTask(title: 'buy milk');
    expect((await laptopSync.sync()).pushed, 2);
    final r = await phoneSync.sync();
    expect(r.pulled, 2);
    expect(r.pushed, 1);
    await laptopSync.sync();

    expect(phone.task(t.id).list, 'Exams');
    expect(laptop.tasks(undated: true).map((x) => x.title).toSet(), {'revise', 'buy milk'});
    final again = await laptopSync.sync();
    expect([again.pulled, again.pushed], [0, 0]);
  });

  test('offline edits on both sides: the later edit wins', () async {
    final t = laptop.addTask(title: 'draft');
    await laptopSync.sync();
    await phoneSync.sync();

    phone.updateTask(t.id, {'title': 'phone edit'});
    await settle();
    laptop.updateTask(t.id, {'title': 'laptop edit'});

    await phoneSync.sync();
    await laptopSync.sync();
    await phoneSync.sync();
    expect(phone.task(t.id).title, 'laptop edit');
    expect(laptop.task(t.id).title, 'laptop edit');
  });

  test('an older edit pushed last does not overwrite a newer one', () async {
    final t = laptop.addTask(title: 'draft');
    await laptopSync.sync();
    await phoneSync.sync();

    phone.updateTask(t.id, {'title': 'older'});
    await settle();
    laptop.updateTask(t.id, {'title': 'newer'});
    await laptopSync.sync();
    await phoneSync.sync();
    expect(phone.task(t.id).title, 'newer');
    expect(remote.tables['tasks']![t.id]!['title'], 'newer');
  });

  test('deletes, ticks and habit checks sync', () async {
    final a = laptop.addTask(title: 'a', date: '2026-10-04');
    final b = laptop.addTask(title: 'b', date: '2026-10-04');
    final h = laptop.addHabit(title: 'Read');
    await laptopSync.sync();
    await phoneSync.sync();

    phone.deleteTask(a.id);
    phone.setDone(b.id, true);
    phone.setHabitCheck(h.id, '2026-10-04', true);
    await phoneSync.sync();
    await laptopSync.sync();

    expect(laptop.tasks().single.id, b.id);
    expect(laptop.task(b.id).done, isTrue);
    expect(laptop.checkedHabitIds('2026-10-04'), {h.id});
  });

  test('a failed push keeps rows dirty for the next attempt', () async {
    laptop.addTask(title: 'kept');
    remote.failPush = true;
    await expectLater(laptopSync.sync(), throwsA(isA<SyncException>()));
    remote.failPush = false;
    expect((await laptopSync.sync()).pushed, 1);
    await phoneSync.sync();
    expect(phone.tasks(undated: true).single.title, 'kept');
  });

  test('reset re-pushes everything to a fresh server', () async {
    laptop.addTask(title: 'x');
    await laptopSync.sync();
    final fresh = FakeRemote();
    SyncEngine.reset(laptop);
    expect((await SyncEngine(laptop, fresh).sync()).pushed, 1);
  });

  test('stamps are fixed width so they order as strings', () {
    final a = utcStamp(DateTime.utc(2026, 10, 3, 12, 0, 0, 41));
    final b = utcStamp(DateTime.utc(2026, 10, 3, 12, 0, 0, 41, 500));
    expect(a, '2026-10-03T12:00:00.041000Z');
    expect(a.compareTo(b), lessThan(0));
  });

  test('screen time from both devices is shared and never overwritten', () async {
    phone.setDeviceName('phone');
    laptop.setDeviceName('laptop');
    UsageSpan span(String app) =>
        UsageSpan(app, app, DateTime(2026, 10, 3, 10), DateTime(2026, 10, 3, 10, 30));
    phone.replaceUsage(DateTime(2026, 10, 3), [span('maps')]);
    laptop.addUsage([span('code')]);
    await phoneSync.sync();
    await laptopSync.sync();
    await phoneSync.sync();
    for (final s in [phone, laptop]) {
      expect(s.usageByDevice('2026-10-03', '2026-10-03'), {'phone': 1800, 'laptop': 1800});
      expect(s.usageByApp('2026-10-03', '2026-10-03', device: 'phone').single.app, 'maps');
    }
  });
}
