import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart';
import 'package:todo_core/todo_core.dart';

import 'sync_test.dart' show FakeRemote;

/// A server that has never heard of some columns, like one whose schema is
/// older than the app: it refuses a write naming them, as PostgREST does.
class OldServer extends FakeRemote implements ReportsMissingColumns {
  OldServer(this.unknown);
  final Map<String, Set<String>> unknown;

  @override
  final missingColumns = <String, Set<String>>{};

  @override
  Future<void> push(String table, List<Map<String, Object?>> rows) {
    final drop = unknown[table] ?? const {};
    if (rows.any((r) => r.keys.any(drop.contains))) missingColumns[table] = {...drop};
    return super.push(table, [
      for (final r in rows) {for (final e in r.entries) if (!drop.contains(e.key)) e.key: e.value},
    ]);
  }
}

void main() {
  late Store store;
  final day = today();
  final tomorrow = addDays(day, 1);

  setUp(() => store = Store(openMemoryDb()));

  group('the migration', () {
    test('keeps every task and entry, and leaves the new fields empty', () {
      final db = sqlite3.openInMemory();
      migrate(db, upTo: 5);
      db.execute(
        "INSERT INTO tasks (id, title, date, start_time, end_time, created_at, updated_at, dirty) "
        "VALUES ('t1', 'Helios release', '2026-10-14', '15:00', '16:45', '2026-10-13T05:00:00.000000Z', '2026-10-13T05:00:00.000000Z', 0)",
      );
      db.execute(
        "INSERT INTO diary (id, date, author, body, created_at, updated_at, dirty) "
        "VALUES ('d1', '2026-10-14', 'me', 'I have to finish Helios', '2026-10-14T13:41:00.000000Z', '2026-10-14T13:41:00.000000Z', 0)",
      );
      migrate(db);
      final old = Store(db);
      final t = old.task('t1');
      expect([t.title, t.date, t.startTime, t.endTime], ['Helios release', '2026-10-14', '15:00', '16:45']);
      expect([t.dueDate, t.estimateMin, t.protect, t.sourceEntry, t.history], everyElement(isNull));
      expect(old.diary().single.outcome, isNull);
      // Migrating changes nothing a server needs to hear about.
      expect(db.select('SELECT COUNT(*) AS n FROM tasks WHERE dirty = 1').first['n'], 0);
    });
  });

  group('a deadline is not the day a task is planned for', () {
    test('moving a task to tomorrow never moves its deadline', () {
      final t = store.addTask(title: "Dad's project", date: day, dueDate: '2026-11-05');
      final moved = store.updateTask(t.id, {'date': tomorrow});
      expect(moved.date, tomorrow);
      expect(moved.dueDate, '2026-11-05');
    });

    test('every change to the day, time or deadline is written to the task history', () {
      final t = store.addTask(title: 'DSA', date: day, startTime: '11:15', endTime: '12:45');
      store.updateTask(t.id, {'date': tomorrow}, reason: 'woke at 11:30');
      store.updateTask(t.id, {'start_time': '13:00', 'end_time': '14:30'});
      store.updateTask(t.id, {'title': 'DSA: Two Sum'}); // not a move: not logged
      final lines = store.task(t.id).history!.split('\n');
      expect(lines, hasLength(2));
      expect(lines.first, endsWith('day $day -> $tomorrow (woke at 11:30)'));
      expect(lines.last, endsWith('time 11:15-12:45 -> 13:00-14:30'));
    });

    test('a task sent back to the backlog loses its time slot, and keeps its deadline', () {
      final t = store.addTask(title: 'Workout', date: day, startTime: '07:00', endTime: '08:00', dueDate: tomorrow);
      final back = store.updateTask(t.id, {'date': null}, reason: 'morning passed');
      expect([back.date, back.startTime, back.endTime, back.dueDate], [null, null, null, tomorrow]);
    });

    test('dates and times that make no sense are refused', () {
      expect(() => store.addTask(title: 'x', dueDate: '2026-02-30'), throwsA(isA<TodoException>()));
      expect(() => store.addTask(title: 'x', date: day, startTime: '14:00', endTime: '13:00'), throwsA(isA<TodoException>()));
      expect(() => store.addTask(title: 'x', protect: 'always'), throwsA(isA<TodoException>()));
      expect(() => store.addTask(title: 'x', sourceEntry: 'no-such-entry'), throwsA(isA<TodoException>()));
    });
  });

  group('protected commitments, as an unattended assistant edits them', () {
    test('one protected on its day can move within the day, not off it without a reason', () {
      final dsa = store.addTask(title: 'DSA', date: day, startTime: '11:15', endTime: '12:45', protect: Task.protectDay);
      store.updateTask(dsa.id, {'start_time': '14:00', 'end_time': '15:30'}, guarded: true);
      expect(() => store.updateTask(dsa.id, {'date': tomorrow}, guarded: true), throwsA(isA<TodoException>()));
      expect(store.task(dsa.id).date, day);
      store.updateTask(dsa.id, {'date': tomorrow}, guarded: true, reason: 'college all day');
      expect(store.task(dsa.id).history, contains('college all day'));
    });

    test('one fixed in time cannot move at all without a reason', () {
      final lecture = store.addTask(title: 'Lecture', date: day, startTime: '09:00', endTime: '10:00', protect: Task.protectTime);
      expect(
        () => store.updateTask(lecture.id, {'start_time': '10:00', 'end_time': '11:00'}, guarded: true),
        throwsA(isA<TodoException>()),
      );
    });

    test('a deadline can only be changed with a reason', () {
      final t = store.addTask(title: 'Post about the CLI', dueDate: addDays(day, 4));
      expect(() => store.updateTask(t.id, {'due_date': addDays(day, 9)}, guarded: true), throwsA(isA<TodoException>()));
      store.updateTask(t.id, {'due_date': addDays(day, 9)}, guarded: true, reason: 'Vibe Forge results come out Friday');
    });

    test('the person themselves, in the app, is never stopped', () {
      final dsa = store.addTask(title: 'DSA', date: day, protect: Task.protectDay);
      store.updateTask(dsa.id, {'date': tomorrow});
      expect(store.task(dsa.id).date, tomorrow);
    });
  });

  group('sync with a server older than the app', () {
    test('values the server cannot hold stay on the device and are pushed again later', () async {
      final server = OldServer({'tasks': {'due_date', 'estimate_min', 'protect', 'source_entry', 'history'}});
      final t = store.addTask(title: "Dad's project", dueDate: '2026-11-05');
      final first = await SyncEngine(store, server).sync();
      expect(first.missingColumns['tasks'], contains('due_date'));
      expect(server.tables['tasks']![t.id]!['title'], "Dad's project");

      // Pulling the row back, without the column, keeps the deadline here.
      store.setMeta('pulled:tasks', null);
      await SyncEngine(store, server).sync();
      expect(store.task(t.id).dueDate, '2026-11-05');

      // Once the server is updated, the deadline arrives.
      server.unknown.clear();
      server.missingColumns.clear();
      final later = await SyncEngine(store, server).sync();
      expect(later.missingColumns, isEmpty);
      expect(server.tables['tasks']![t.id]!['due_date'], '2026-11-05');
    });
  });

  group('the plan check', () {
    final morning = DateTime.now().copyWith(hour: 1, minute: 5);

    test('a sensible plan passes', () {
      store.addTask(title: 'DSA', date: day, startTime: '12:00', endTime: '13:30', protect: Task.protectDay);
      store.addTask(title: 'Helios', date: day, startTime: '15:00', endTime: '16:45');
      final check = store.checkPlan(day, wake: '10:00', now: morning);
      expect(check.errors.map((e) => e.message), isEmpty);
      expect(check.ok, isTrue);
    });

    test('a task left in the past, a broken deadline and a task after its deadline are errors', () {
      store.addTask(title: 'Workout', date: addDays(day, -1));
      store.addTask(title: 'Submit form', dueDate: addDays(day, -2));
      store.addTask(title: 'Post', date: addDays(day, 3), dueDate: addDays(day, 2));
      final codes = store.checkPlan(day, now: morning).errors.map((e) => e.code);
      expect(codes, containsAll(['overdue', 'deadline_passed', 'after_deadline']));
    });

    test('after three late nights the day starts when you actually wake, not at 06:30', () {
      // Signs of life: the phone in use from 11:00 on each of the last three days.
      for (var back = 1; back <= 3; back++) {
        final d = addDays(day, -back);
        store.addUsage([UsageSpan('chat', 'Messages', atTime(d, '11:00'), atTime(d, '11:40'))]);
      }
      expect(store.stats(days: 7).wakeOver(3), 11 * 60);
      store.addTask(title: 'Workout', date: day, startTime: '07:00', endTime: '08:00');
      final check = store.checkPlan(day, now: morning);
      expect(check.toJson()['day_starts'], '12:00');
      expect(check.errors.single.code, 'before_start');
    });

    test('staying up until five is a late night, not an early start', () {
      final d = addDays(day, -1);
      // Up until 05:00 the night before, then asleep until about noon.
      store.addUsage([UsageSpan('video', 'Videos', atTime(addDays(d, -1), '23:00'), atTime(d, '05:00'))]);
      store.addUsage([UsageSpan('chat', 'Messages', atTime(d, '12:10'), atTime(d, '12:40'))]);
      final record = store.stats(days: 2).days.firstWhere((r) => r.date == d);
      expect(clockText(record.wake!), '12:00');
      expect(clockText(store.stats(days: 3).days.firstWhere((r) => r.date == addDays(d, -1)).bed!), '04:59');
    });

    test('a day fuller than 75% of the time available is overloaded', () {
      for (var h = 12; h < 22; h++) {
        store.addTask(title: 'Block $h', date: day, startTime: '$h:00', endTime: '$h:55');
      }
      final check = store.checkPlan(day, wake: '11:00', now: morning);
      expect(check.errors.map((e) => e.code), contains('overloaded'));
      expect(check.budgetMin, ((22 * 60 + 30 - 12 * 60) * 0.75).floor());
    });

    test('overlapping blocks are caught', () {
      store.addTask(title: 'A', date: day, startTime: '12:00', endTime: '13:00');
      store.addTask(title: 'B', date: day, startTime: '12:30', endTime: '13:30');
      expect(store.checkPlan(day, wake: '10:00', now: morning).errors.map((e) => e.code), contains('overlap'));
    });

    test('a protected task moved today is something the report must mention', () {
      final dsa = store.addTask(title: 'DSA', date: day, protect: Task.protectDay);
      store.updateTask(dsa.id, {'date': tomorrow}, reason: 'woke at 15:00');
      final warning = store.checkPlan(day, wake: '10:00').warnings.single;
      expect(warning.code, 'protected_moved');
      expect(warning.message, contains('woke at 15:00'));
    });
  });

  group('the entry that lost a whole list', () {
    // The 14 Oct entry: eight things to do, all filed as ideas, none kept.
    const entry =
        "I wanna get a international internship somehow. Gonna post about my cli to do this week with my vibe forge win. "
        'I have to get the Helios project done and put it out there as well. I gotta finish the asha worker project as well. '
        'I have to study the NetWM project thoroughly as well. Ansh mentioned a lot of stuff i have to go thru them and organize them into tasks. '
        "I have to use the claude credits to do my father's project as well, credits will expire on nov 5.";
    final commitments = {
      'Post about the CLI todo and the Vibe Forge win': (due: addDays(day, 4), project: 'Personal brand'),
      'Finish Helios and put it out': (due: null, project: 'Helios'),
      'Finish the ASHA worker project': (due: null, project: 'ASHA worker'),
      'Study NetWM thoroughly': (due: null, project: 'NetWM'),
      "Turn Ansh's suggestions into tasks": (due: null, project: null),
      "Dad's project, before the Claude credits expire": (due: '2026-11-05', project: "Dad's project"),
      'Apply for international internships': (due: null, project: 'Internships'),
      'Find out what earning sooner could look like': (due: null, project: null),
    };

    test('an entry nobody has processed blocks the plan', () {
      store.addDiary(entry);
      final check = store.checkPlan(day, wake: '11:30', now: DateTime.now().copyWith(hour: 1));
      expect(check.errors.single.code, 'unprocessed_entry');
    });

    test('all eight commitments are kept, linked to the entry, and only five may land on one day', () {
      final e = store.addDiary(entry);
      final captured = [
        for (final MapEntry(key: title, value: c) in commitments.entries)
          store.addTask(
            title: title,
            dueDate: c.due,
            listId: c.project == null ? null : store.ensureList(c.project!).id,
            sourceEntry: e.id,
          ),
      ];
      store.setDiaryOutcome(e.id, '8 commitments captured to the backlog; 1 with a deadline of 5 Nov.');

      expect(store.tasksFromEntry(e.id), hasLength(8));
      expect(store.tasksFromEntry(e.id).where((t) => t.dueDate == '2026-11-05').single.list, "Dad's project");
      expect(store.unprocessedDiary(), isEmpty);

      final checkAt = DateTime.now().add(const Duration(minutes: 1));
      // Five of them in the day: allowed.
      for (final t in captured.take(5)) {
        store.updateTask(t.id, {'date': day, 'estimate_min': 20});
      }
      expect(store.checkPlan(day, wake: '06:00', now: checkAt).errors.map((e) => e.code), isNot(contains('too_many_new')));
      // A sixth: refused, the rest wait in the backlog.
      store.updateTask(captured[5].id, {'date': day, 'estimate_min': 20});
      expect(store.checkPlan(day, wake: '06:00', now: checkAt).errors.map((e) => e.code), contains('too_many_new'));
    });
  });
}
