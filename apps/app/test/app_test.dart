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

  testWidgets('ticking a task on the phone layout updates the store and progress', (tester) async {
    final t = state.store.addTask(title: 'Revise OS', date: today(), startTime: '15:00', tag: 'Exam prep');
    state.store.addTask(title: 'Old one', date: addDays(today(), -1));
    await pump(tester, const Size(390, 800));

    expect(find.text('Revise OS'), findsOneWidget);
    expect(find.text('15:00 · Exam prep'), findsOneWidget);
    expect(find.text('0 of 1 done'), findsOneWidget);
    expect(find.text('1 overdue'), findsOneWidget);
    expect(find.byType(NavigationBar), findsOneWidget);

    await tester.tap(find.byType(Checkbox).first);
    await tester.pump();
    expect(state.store.task(t.id).done, isTrue);
    expect(find.text('1 of 1 done'), findsOneWidget);
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
    expect(find.text('Buy milk'), findsOneWidget);
  });

  testWidgets('habits, plan and focus pages render on phone and desktop widths', (tester) async {
    final h = state.store.addHabit(title: 'Water 4 L');
    state.store.addTask(title: 'Karpathy 1', date: addDays(today(), 5), listId: state.store.ensureList('90 days').id);
    for (final size in const [Size(360, 740), Size(1200, 800)]) {
      await pump(tester, size);
      for (final label in ['Plan', 'Habits', 'Focus', 'Today']) {
        await tester.tap(find.text(label).last);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: '$label at $size');
      }
    }
    expect(find.byType(NavigationRail), findsOneWidget);

    await tester.tap(find.text('Habits').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byType(Checkbox).last);
    await tester.pump();
    expect(state.store.checkedHabitIds(today()), {h.id});

    await tester.tap(find.text('Focus').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Start focus'));
    await tester.pump();
    expect(state.store.currentFocus()!.plannedMin, 25);
    expect(find.text('Stop'), findsOneWidget);
    await tester.tap(find.text('Stop'));
    await tester.pump();
    expect(state.store.currentFocus(), isNull);
  });
}
