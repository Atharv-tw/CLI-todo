import 'dart:convert';
// Draws the pictures the website uses, from made-up data and never your own:
// it fills a store in memory, opens each page and saves it to site/img.
//
//   ../../scripts/screenshots.sh
//
// which runs this with the clock set to mid-afternoon, so the day in the
// pictures is half done whenever they are taken.
import 'dart:io';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:vault_app/diary_page.dart';
import 'package:vault_app/main.dart';
import 'package:vault_app/reminder_page.dart';
import 'package:vault_app/reminders.dart';
import 'package:vault_app/state.dart';
import 'package:vault_app/welcome_page.dart';
import 'package:vault_core/vault_core.dart';

const _frame = ValueKey('screenshot');
final _out = Directory(p.join('..', '..', 'site', 'img'));

Future<void> _loadFonts() async {
  final fonts = p.join(Platform.environment['FLUTTER_ROOT']!, 'bin', 'cache', 'artifacts', 'material_fonts');
  Future<ByteData> font(String file) async => ByteData.sublistView(File(p.join(fonts, file)).readAsBytesSync());
  final roboto = FontLoader('Roboto');
  for (final weight in ['Light', 'Regular', 'Medium', 'Bold', 'Black']) {
    roboto.addFont(font('Roboto-$weight.ttf'));
  }
  await roboto.load();
  await (FontLoader('MaterialIcons')..addFont(font('MaterialIcons-Regular.otf'))).load();
}

/// A day in the life of someone writing a thesis, with half a year behind it.
Store _demo() {
  final store = Store(openMemoryDb());
  final now = today();
  final random = Random(7);

  final thesis = store.ensureList('Thesis').id;
  final home = store.ensureList('Home').id;

  Task task(String title, String date, String time, {String? list, String? tag, bool done = false, String? notes}) {
    final times = time.split('-');
    final t = store.addTask(
      title: title,
      date: date,
      startTime: times.first,
      endTime: times.length > 1 ? times.last : null,
      listId: list,
      tag: tag,
      notes: notes,
    );
    return done ? store.setDone(t.id, true) : t;
  }

  // Today. The script runs this between 14:00 and 15:00, so the paper
  // reading is the task on now.
  task('Morning run, 5 km', now, '07:00-07:45', tag: 'Fitness', done: true);
  final methods = task('Write the methods section', now, '09:00-11:00', list: thesis, tag: 'Writing', done: true);
  task('Reply to my supervisor\'s comments', now, '11:15-12:00', list: thesis, done: true);
  final reading = task(
    'Read two papers on graph sampling',
    now,
    '14:00-15:30',
    list: thesis,
    tag: 'Reading',
    notes: 'Note the sampling method and one open question from each.',
  );
  task('Groceries for the week', now, '16:00-16:30', list: home);
  task('Guitar: practise the new piece', now, '17:00-18:00', tag: 'Music');
  task('Plan tomorrow', now, '21:00-21:15');

  // The days ahead.
  task('Draw the sampling diagram', addDays(now, 1), '09:00-10:30', list: thesis, tag: 'Writing');
  task('Lab meeting', addDays(now, 1), '11:00-12:00', list: thesis);
  task('Pay the electricity bill', addDays(now, 1), '18:00-18:15', list: home);
  task('Results section: first draft', addDays(now, 2), '09:00-11:30', list: thesis, tag: 'Writing');
  task('Long run, 10 km', addDays(now, 3), '07:00-08:15', tag: 'Fitness');
  task('Send chapter 3 to my supervisor', addDays(now, 4), '16:00-16:30', list: thesis);
  task('Book train tickets home', addDays(now, 12), '19:00-19:15', list: home);

  // Habits, half a year old. Two are groups: one habit made of timed steps.
  const days = 182;
  final start = addDays(now, -days);
  Habit habit(String title, String time) => store.addHabit(title: title, time: time, startDate: start);
  final habits = [
    habit('Wake up at 6:30', '06:30'),
    habit('Three meals / Breakfast', '08:00'),
    habit('Three meals / Lunch', '13:00'),
    habit('Three meals / Dinner', '19:30'),
    habit('Water 3 L / 1 L down', '11:00'),
    habit('Water 3 L / 2 L down', '15:00'),
    habit('Water 3 L / 3 L down', '20:00'),
    habit('Read 20 minutes', '22:00'),
    habit('Write three good things', '22:15'),
  ];
  // A past that got steadier: patchy at first, nearly every day lately, with
  // the odd day off.
  const off = {25, 57, 58, 96, 121, 122, 123, 160};
  for (var back = days; back >= 1; back--) {
    if (off.contains(back)) continue;
    final date = addDays(now, -back);
    final steady = back <= 16 ? 0.97 : 0.3 + 0.6 * (days - back) / days;
    for (final h in habits) {
      if (random.nextDouble() < steady) store.setHabitCheck(h.id, date, true);
    }
    if (back % 3 != 0) {
      store.setDone(store.addTask(title: 'Thesis writing', date: date, startTime: '09:00', endTime: '11:00').id, true);
    }
  }
  for (final i in [0, 1, 2, 4]) {
    store.setHabitCheck(habits[i].id, now, true);
  }

  // Focus: two sessions done this morning.
  for (var i = 0; i < 2; i++) {
    store.startFocus(taskId: methods.id, minutes: 50);
    store.stopFocus();
  }
  final morning = atTime(now, '09:05').toUtc();
  var n = 0;
  for (final row in store.db.select('SELECT id FROM focus_sessions')) {
    final from = morning.add(Duration(minutes: 60 * n++));
    store.db.execute('UPDATE focus_sessions SET started_at = ?, ended_at = ? WHERE id = ?', [
      utcStamp(from.toLocal()),
      utcStamp(from.add(const Duration(minutes: 50)).toLocal()),
      row['id'],
    ]);
  }

  // Screen time on two devices, for a week.
  void usage(String device, List<(String, String, String, int)> spans, int back) {
    store
      ..setMeta('device_id', device)
      ..setDeviceName(device);
    final date = addDays(now, -back);
    store.addUsage([
      for (final (app, name, at, minutes) in spans)
        UsageSpan(app, name, atTime(date, at), atTime(date, at).add(Duration(minutes: minutes))),
    ]);
  }

  for (var back = 6; back >= 0; back--) {
    final less = back == 0 ? 0.55 : 1.0; // today is only half over
    int m(int minutes) => (minutes * less * (0.75 + random.nextDouble() * 0.5)).round();
    usage('laptop', [
      ('editor', 'Editor', '09:00', m(100)),
      ('browser', 'Browser', '11:00', m(55)),
      ('terminal', 'Terminal', '12:00', m(35)),
      ('pdf', 'Documents', '13:00', m(50)),
    ], back);
    usage('phone', [
      ('chat', 'Messages', '08:00', m(30)),
      ('video', 'Videos', '13:00', m(45)),
      ('music', 'Music', '10:00', m(25)),
      ('maps', 'Maps', '12:00', m(10)),
    ], back);
  }

  // The diary: the day so far, and the note the assistant left overnight.
  void entry(String at, String body, {String author = DiaryEntry.me, String? taskId}) {
    final e = store.addDiary(body, author: author, taskId: taskId);
    store.db.execute('UPDATE diary SET created_at = ? WHERE id = ?', [utcStamp(atTime(now, at)), e.id]);
  }

  entry('01:00', 'Handled the diary up to 01:00. Moved Guitar to 17:00 to leave room for the lab meeting notes.',
      author: DiaryEntry.assistant);
  entry('07:50', 'Up at 6:40. The run felt easy today.');
  entry('11:05', 'Took the full two hours. The sampling part needs a diagram.', taskId: methods.id);
  entry('12:20', 'Idea: record a two-minute summary after every paper, so the literature review writes itself.');
  entry('13:40', 'Decided to drop the second experiment. One done well beats two rushed.');

  // Earlier days, which the Diary folds into one tile each.
  const earlier = [
    ['Long day in the lab. The second run finally converged.', 'Decided to write every morning before email.'],
    ['Slept badly, kept the run short.', 'Outlined chapter 3 on paper first. Much faster than typing.'],
    ['Supervisor liked the framing. Wants one more baseline.'],
    ['Rest day. Read a novel for two hours.'],
    ['Idea: plot error against sample size, not against time.', 'Guitar felt easier today.'],
    ['Groceries, laundry, an early night.'],
  ];
  for (final (i, texts) in earlier.indexed) {
    final date = addDays(now, -(i + 1));
    for (final (n, body) in texts.indexed) {
      final e = store.addDiary(body, date: date);
      store.db.execute('UPDATE diary SET created_at = ? WHERE id = ?', [utcStamp(atTime(date, n == 0 ? '08:10' : '21:40')), e.id]);
    }
  }

  store.setMeta('demo_reading', reading.id);
  store.setMeta(welcomedKey, '1');

  // What the laptop's vault publishes for the phone.
  store
    ..putPage(
      'morning',
      now,
      '# ${prettyDate(now)}\n\n## The day\n\nStarts 07:00 (woke 06:40, said in the diary).\n\n'
          '- **07:00–08:00** Run, 5 km\n- **09:00–11:00** Write the methods section\n'
          '- **14:00–15:30** Supervisor meeting\n- **17:00–18:30** Analysis: error against sample size\n\n'
          'Must-dos: the methods draft, the meeting notes, an early night.\n\n'
          '## Facts\n\n- Yesterday: 5 of 6 done.\n- Due this week: the methods draft (Fri).\n\n'
          '## Guesses\n\n- The analysis needs 90 minutes, from your last three sessions.\n\n'
          '## Waiting for your yes\n\n- Move "Guitar" to 21:00 on weekdays? It was skipped 4 of 5 days at 19:00.\n\n'
          '## Open questions\n\n- Should the second experiment come back after the draft?',
      title: prettyDate(now),
    )
    ..putPage('goals', 'all', 'Submit the thesis by March\nRun a half marathon\nPlay one full song on guitar')
    ..putPage(
      'me',
      'me',
      '# Me\n\nCall me Sam.\n\n## Goals\n\n- Submit the thesis by March.\n- Run a half marathon.\n'
          '- Play one full song on guitar.\n\n## How I like my day planned\n\n- Wake up: 06:40\n- Asleep by: 23:00',
      title: 'Me',
    )
    ..putPage(
      'projects',
      'all',
      jsonEncode([
        {
          'name': 'Thesis',
          'status': 'building',
          'what': 'Uncertainty in small-sample models',
          'overview': '# Thesis\n\n**What it is:** my final-year thesis on uncertainty in small-sample models.',
        },
        {
          'name': 'Half marathon',
          'status': 'building',
          'what': 'Training plan towards a race in spring',
          'overview': '# Half marathon\n\nTraining towards a race in spring.',
        },
        {
          'name': 'Reading group',
          'status': 'role',
          'what': 'I run the lab\'s weekly paper reading',
          'overview': '# Reading group\n\nThe lab\'s weekly paper reading.',
        },
      ]),
    );
  return store;
}

void main() {
  late AppState state;

  setUpAll(() async {
    await _loadFonts();
    _out.createSync(recursive: true);
  });
  setUp(() => state = AppState(_demo()));
  tearDown(() => state.dispose());

  Future<void> open(WidgetTester tester, Size size) async {
    // Tests draw shadows as flat outlines; these are pictures, so draw them
    // properly. Each test puts this back before it ends.
    debugDisableShadows = false;
    tester.view
      ..physicalSize = size
      ..devicePixelRatio = 1
      // Room for a status bar, as on a phone.
      ..padding = FakeViewPadding(top: size.width < 600 ? 28 : 0);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(RepaintBoundary(key: _frame, child: TodoApp(state: state)));
    await tester.pumpAndSettle();
  }

  Future<void> shoot(WidgetTester tester, String name) async {
    final boundary = tester.renderObject<RenderRepaintBoundary>(find.byKey(_frame));
    await tester.runAsync(() async {
      final image = await boundary.toImage(pixelRatio: 2);
      final png = await image.toByteData(format: ui.ImageByteFormat.png);
      File(p.join(_out.path, '$name.png')).writeAsBytesSync(png!.buffer.asUint8List());
    });
  }

  Future<void> go(WidgetTester tester, String page) async {
    final pill = find.byKey(ValueKey('nav-$page'));
    await tester.tap(pill.evaluate().isNotEmpty ? pill : find.text(page).last);
    await tester.pumpAndSettle();
  }

  const phone = Size(390, 844);

  testWidgets('the pages, on a phone', (tester) async {
    expect(DateTime.now().hour, 14, reason: 'Run scripts/screenshots.sh, which sets the clock.');
    await open(tester, phone);
    await shoot(tester, 'brain');
    for (final (page, name) in [('To-do', 'today'), ('Diary', 'diary'), ('Profile', 'profile')]) {
      await go(tester, page);
      await shoot(tester, name);
      if (page == 'Diary') {
        // Further down: the days that are over, one tile each, one opened.
        final yesterday = find.byKey(ValueKey('diary-day-${addDays(today(), -1)}'));
        final list = find.descendant(of: find.byType(DiaryPage), matching: find.byType(Scrollable)).first;
        await tester.scrollUntilVisible(yesterday, 200, scrollable: list);
        await tester.tap(yesterday);
        await tester.pumpAndSettle();
        await tester.drag(list, const Offset(0, -260));
        await tester.pumpAndSettle();
        await shoot(tester, 'diary-earlier');
      }
    }
    // Focus opens from the button at the top; shown with a session under way.
    await tester.tap(find.byTooltip('Focus'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Start focus'));
    await tester.pumpAndSettle();
    await shoot(tester, 'focus');
    state.change((s) => s.stopFocus());
    await tester.pumpAndSettle();
    debugDisableShadows = true;
  });

  testWidgets('the full-screen reminder', (tester) async {
    await open(tester, phone);
    final reading = state.store.task(state.store.getMeta('demo_reading')!);
    tester.state<NavigatorState>(find.byType(Navigator).first).push(MaterialPageRoute<void>(
          builder: (_) => ReminderPage(Reminder(
            kind: 'task',
            id: reading.id,
            date: reading.date!,
            title: reading.title,
            start: reading.startTime!,
            end: reading.endTime,
          )),
        ));
    await tester.pumpAndSettle();
    await shoot(tester, 'reminder');
    debugDisableShadows = true;
  });

  testWidgets('the desktop app', (tester) async {
    await open(tester, const Size(1280, 800));
    await shoot(tester, 'desktop');
    debugDisableShadows = true;
  });
}
