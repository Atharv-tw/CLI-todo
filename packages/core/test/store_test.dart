import 'package:test/test.dart';
import 'package:todo_core/todo_core.dart';

void main() {
  late Store store;
  setUp(() => store = Store(openMemoryDb()));

  group('dates', () {
    final sat = DateTime(2026, 10, 3);
    test('relative forms', () {
      expect(parseDate('today', now: sat), '2026-10-03');
      expect(parseDate('tomorrow', now: sat), '2026-10-04');
      expect(parseDate('+3', now: sat), '2026-10-06');
      expect(parseDate('mon', now: sat), '2026-10-05');
      expect(parseDate('Saturday', now: sat), '2026-10-10');
      expect(parseDate('2026-11-9', now: sat), '2026-11-09');
    });
    test('rejects junk and impossible dates', () {
      expect(() => parseDate('soon'), throwsFormatException);
      expect(() => parseDate('2026-02-30'), throwsFormatException);
    });
    test('time ranges', () {
      expect(parseTimeRange('17:50–18:50'), ('17:50', '18:50'));
      expect(parseTimeRange('9'), ('09:00', null));
      expect(() => parseTimeRange('25:00'), throwsFormatException);
    });
  });

  group('tasks', () {
    test('ordered by date then time, undated last', () {
      store.addTask(title: 'late', date: '2026-10-03', startTime: '18:00');
      store.addTask(title: 'undated');
      store.addTask(title: 'early', date: '2026-10-03', startTime: '08:30');
      store.addTask(title: 'no time', date: '2026-10-03');
      store.addTask(title: 'next day', date: '2026-10-04');
      expect(
        store.tasks(undated: true).map((t) => t.title),
        ['early', 'late', 'no time', 'next day', 'undated'],
      );
      expect(store.tasks(from: '2026-10-04', to: '2026-10-04').single.title, 'next day');
    });

    test('done, undo, overdue, delete', () {
      final a = store.addTask(title: 'a', date: '2026-10-01');
      final b = store.addTask(title: 'b', date: '2026-10-02');
      expect(store.tasks(overdueBefore: '2026-10-03'), hasLength(2));
      expect(store.setDone(a.id, true).done, isTrue);
      expect(store.tasks(overdueBefore: '2026-10-03').single.id, b.id);
      expect(store.setDone(a.id, false).done, isFalse);
      store.deleteTask(b.id);
      expect(store.tasks().single.id, a.id);
    });

    test('update clears fields and joins the list title', () {
      final list = store.ensureList('Exams');
      final t = store.addTask(title: 'x', date: '2026-10-05', tag: 'prep', listId: list.id);
      expect(t.list, 'Exams');
      final u = store.updateTask(t.id, {'tag': null, 'date': '2026-10-06'});
      expect(u.tag, isNull);
      expect(u.date, '2026-10-06');
      expect(() => store.updateTask(t.id, {'id': 'nope'}), throwsA(isA<TodoException>()));
    });

    test('id prefixes resolve only when unique', () {
      final t = store.addTask(title: 'x');
      expect(store.resolveId('tasks', t.id.substring(0, 8)), t.id);
      store.addTask(title: 'y');
      expect(() => store.resolveId('tasks', ''), throwsA(isA<TodoException>()));
      expect(() => store.resolveId('tasks', 'zzz'), throwsA(isA<TodoException>()));
    });

    test('ensureList reuses a list regardless of case', () {
      expect(store.ensureList('exams').id, store.ensureList('Exams').id);
      expect(store.lists(), hasLength(1));
    });
  });

  group('habits', () {
    test('active range and checks', () {
      final always = store.addHabit(title: 'Water', startDate: '2026-10-01', endDate: '2026-12-29');
      final later = store.addHabit(title: 'DSA', startDate: '2026-10-11', endDate: '2026-12-29');
      expect(store.habits(activeOn: '2026-10-03').single.id, always.id);
      expect(store.habits(activeOn: '2026-10-11'), hasLength(2));
      expect(store.habits(activeOn: '2026-12-30'), isEmpty);

      store.setHabitCheck(later.id, '2026-10-11', true);
      expect(store.checkedHabitIds('2026-10-11'), {later.id});
      expect(store.checkedHabitIds('2026-10-12'), isEmpty);
      store.setHabitCheck(later.id, '2026-10-11', false);
      expect(store.checkedHabitIds('2026-10-11'), isEmpty);
      expect(store.resolveHabit('dsa'), later.id);
    });
  });

  group('focus', () {
    test('one session at a time', () {
      final t = store.addTask(title: 'revise');
      final first = store.startFocus(taskId: t.id, minutes: 25);
      expect(store.currentFocus()!.taskTitle, 'revise');
      final second = store.startFocus(minutes: 5, kind: 'break');
      expect(store.currentFocus()!.id, second.id);
      final ended = store.db.select('SELECT ended_at FROM focus_sessions WHERE id = ?', [first.id]);
      expect(ended.first['ended_at'], isNotNull);
      expect(store.stopFocus()!.id, second.id);
      expect(store.currentFocus(), isNull);
      expect(store.stopFocus(), isNull);
    });

    test('a forgotten session is closed at its planned end', () {
      final start = DateTime.now().subtract(const Duration(hours: 3)).toUtc();
      store.db.execute(
        "INSERT INTO focus_sessions (id, kind, started_at, planned_min, created_at, updated_at) "
        "VALUES ('old', 'focus', ?1, 50, ?1, ?1)",
        [start.toIso8601String()],
      );
      expect(store.currentFocus(), isNull);
      expect(store.focusedMinutes(ymd(start.toLocal())), 50);
    });
  });

  test('snapshot items merge tasks and habits in time order', () {
    final day = today();
    store.addTask(title: 'afternoon task', date: day, startTime: '14:30');
    store.addTask(title: 'untimed task', date: day);
    store.addHabit(title: 'Read', time: '22:15');
    final train = store.addHabit(title: 'Train', time: '07:00');
    store.addHabit(title: 'Protein');
    store.setHabitCheck(train.id, day, true);
    final items = store.snapshot()['items'] as List;
    expect(items.map((i) => i['title']), ['Train', 'afternoon task', 'Read', 'untimed task', 'Protein']);
    expect(items.map((i) => i['kind']), ['habit', 'task', 'habit', 'task', 'habit']);
    expect(items.first['done'], isTrue);
    store.setHabitTime(train.id, null);
    expect(
      (store.snapshot()['items'] as List).map((i) => i['title']),
      ['afternoon task', 'Read', 'untimed task', 'Train', 'Protein'],
    );
  });

  test('upcoming lists unticked timed items across days', () {
    final day = today();
    final a = store.addTask(title: 'a', date: day, startTime: '09:00', endTime: '10:00');
    store.addTask(title: 'untimed', date: day);
    store.addTask(title: 'b', date: addDays(day, 1), startTime: '08:00');
    store.addTask(title: 'far', date: addDays(day, 5), startTime: '08:00');
    store.addHabit(title: 'Train', time: '07:00');
    store.setDone(a.id, true);
    final up = store.upcoming(fromDate: day, days: 2);
    expect(up.map((i) => '${i['date'] == day ? 'd0' : 'd1'} ${i['title']}'), ['d0 Train', 'd1 Train', 'd1 b']);
    expect(slotEnd(day, '09:00', null).difference(atTime(day, '09:00')).inMinutes, 30);
    expect(hm(slotEnd(day, '09:00', '10:15')), '10:15');
  });

  group('streaks', () {
    test('a gap breaks a streak; today unticked does not', () {
      final h = store.addHabit(title: 'Read');
      for (final d in ['2026-10-01', '2026-10-02', '2026-10-03', '2026-10-05', '2026-10-06']) {
        store.setHabitCheck(h.id, d, true);
      }
      expect(store.habitStreak(h.id, '2026-10-06'), (current: 2, best: 3));
      expect(store.habitStreak(h.id, '2026-10-07'), (current: 2, best: 3));
      expect(store.habitStreak(h.id, '2026-10-08'), (current: 0, best: 3));
      store.setHabitCheck(h.id, '2026-10-04', true);
      expect(store.habitStreak(h.id, '2026-10-06'), (current: 6, best: 6));
      expect(store.habitDays(h.id, '2026-10-02', '2026-10-03'), {'2026-10-02', '2026-10-03'});
    });

    test('day completion counts tasks and habits active that day', () {
      final a = store.addTask(title: 'a', date: '2026-10-02');
      store.addTask(title: 'b', date: '2026-10-02');
      final always = store.addHabit(title: 'Water');
      final later = store.addHabit(title: 'DSA', startDate: '2026-10-03');
      store.setDone(a.id, true);
      store.setHabitCheck(always.id, '2026-10-02', true);
      store.setHabitCheck(later.id, '2026-10-03', true);
      final c = store.dayCompletion('2026-10-01', '2026-10-03');
      expect(c['2026-10-01'], (done: 0, total: 1));
      expect(c['2026-10-02'], (done: 2, total: 3));
      expect(c['2026-10-03'], (done: 1, total: 2));
      expect(store.overallStreak('2026-10-03'), (current: 2, best: 2));
      expect(store.dayCompletion('2026-10-02', '2026-10-02', tasks: false)['2026-10-02'], (done: 1, total: 1));
      store.setHabitCheck(always.id, '2026-10-02', false);
      expect(store.overallStreak('2026-10-03', false), (current: 1, best: 1));
      expect(store.overallStreak('2026-10-03'), (current: 2, best: 2));
      store.setHabitCheck(always.id, '2026-10-02', true);
      store.deleteHabit(later.id);
      expect(store.dayCompletion('2026-10-03', '2026-10-03')['2026-10-03'], (done: 0, total: 1));
    });
  });

  test('snapshot covers one day', () {
    final day = today();
    final t = store.addTask(title: 'now', date: day);
    store.addTask(title: 'old', date: addDays(day, -1));
    store.setDone(t.id, true);
    final h = store.addHabit(title: 'Read');
    store.setHabitCheck(h.id, day, true);
    final snap = store.snapshot();
    expect(snap['done'], 1);
    expect(snap['open'], 0);
    expect(snap['overdue'], 1);
    expect((snap['habits'] as List).single, {'id': h.id, 'title': 'Read', 'time': null, 'done': true});
    expect(snap['focus'], isNull);
  });
}
