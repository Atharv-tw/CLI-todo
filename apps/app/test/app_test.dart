import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:todo_app/main.dart';
import 'package:todo_app/state.dart';
import 'package:todo_core/todo_core.dart';

void main() {
  late AppState state;

  setUp(() => state = AppState(Store(openMemoryDb())));
  tearDown(() => state.dispose());

  Future<void> pump(WidgetTester tester, Size size) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(TodoApp(state: state));
  }

  Future<void> go(WidgetTester tester, String page) async {
    final pill = find.byKey(ValueKey('nav-$page'));
    await tester.tap(pill.evaluate().isNotEmpty ? pill : find.text(page).last);
    await tester.pumpAndSettle();
  }

  testWidgets('ticking from the timeline updates the store and the progress card', (tester) async {
    final t = state.store.addTask(title: 'Revise OS', date: today(), startTime: '00:00', endTime: '00:01');
    final h = state.store.addHabit(title: 'Train', time: '00:02');
    state.store.addTask(title: 'Old one', date: addDays(today(), -1));
    await pump(tester, const Size(390, 800));

    // Once in the "Up next" card, once on the timeline.
    expect(find.text('Revise OS'), findsNWidgets(2));
    expect(find.text('0 of 2 done'), findsOneWidget);
    expect(find.text('1 overdue'), findsNWidgets(2));

    await tester.tap(find.byKey(ValueKey('timeline-${t.id}')));
    await tester.pump();
    expect(state.store.task(t.id).done, isTrue);
    expect(find.text('1 of 2 done'), findsOneWidget);
    expect(find.text('Revise OS'), findsOneWidget);

    await tester.tap(find.byKey(ValueKey('timeline-${h.id}')));
    await tester.pump();
    expect(state.store.checkedHabitIds(today()), {h.id});
    expect(find.text('2 of 2 done'), findsOneWidget);
    expect(find.text('All done'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('adding a task through the sheet', (tester) async {
    await pump(tester, const Size(390, 800));
    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, 'Task'), 'Buy milk');
    await tester.tap(find.text('Add task'));
    await tester.pumpAndSettle();
    expect(state.store.tasks(from: today(), to: today()).single.title, 'Buy milk');
    expect(find.text('Buy milk'), findsWidgets);
  });

  testWidgets('every page lays out without overflow at phone and desktop widths', (tester) async {
    state.store.addHabit(title: 'Water 4 L', time: '21:00');
    state.store.addHabit(title: 'A habit with quite a long name to wrap', startDate: addDays(today(), 3));
    state.store.addTask(
      title: 'Computer Networks assignment 2, then Software Engineering assignment 1',
      date: today(),
      startTime: '11:30',
      endTime: '13:45',
      tag: 'Assignments',
      listId: state.store.ensureList('Mid-sems').id,
    );
    state.store.addTask(title: 'Karpathy 1', date: addDays(today(), 5));
    for (final size in const [Size(360, 740), Size(390, 844), Size(1200, 800)]) {
      await pump(tester, size);
      for (final page in ['Plan', 'Habits', 'Focus', 'Today']) {
        await go(tester, page);
        expect(tester.takeException(), isNull, reason: '$page at $size');
      }
    }
    expect(find.byType(NavigationRail), findsOneWidget);
  });

  testWidgets('habit grid: done today, and toggling a past day', (tester) async {
    final h = state.store.addHabit(title: 'Read', startDate: addDays(today(), -40));
    await pump(tester, const Size(390, 844));
    await go(tester, 'Habits');

    await tester.tap(find.byKey(ValueKey('done-${h.id}')));
    await tester.pump();
    expect(state.store.checkedHabitIds(today()), {h.id});
    expect(find.text('Undo today'), findsOneWidget);
    expect(find.text('1 day'), findsWidgets);

    // The first of the month is on screen unless today is the first.
    final first = ymd(DateTime(DateTime.now().year, DateTime.now().month, 1));
    if (first != today()) {
      final cell = find.byKey(ValueKey('heat-${h.id}-$first'));
      await tester.ensureVisible(cell);
      await tester.tap(cell);
      await tester.pump();
      expect(state.store.habitDays(h.id, first, first), {first});
      await tester.tap(cell);
      await tester.pump();
      expect(state.store.habitDays(h.id, first, first), isEmpty);
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('focus starts and stops from the Focus page', (tester) async {
    await pump(tester, const Size(390, 844));
    await go(tester, 'Focus');
    await tester.tap(find.text('Start focus'));
    await tester.pump();
    expect(state.store.currentFocus()!.plannedMin, 25);
    await tester.tap(find.text('Stop'));
    await tester.pump();
    expect(state.store.currentFocus(), isNull);
  });
}
