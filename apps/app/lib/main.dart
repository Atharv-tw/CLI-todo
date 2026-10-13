import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:home_widget/home_widget.dart';
import 'package:todo_core/todo_core.dart';

import 'background.dart';
import 'diary_page.dart';
import 'focus_page.dart';
import 'habits_page.dart';
import 'plan_page.dart';
import 'reminder_page.dart';
import 'reminders.dart';
import 'screen_page.dart';
import 'state.dart';
import 'sync_page.dart';
import 'theme.dart';
import 'today_page.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final path = await appDbPath();
  if (Platform.isAndroid) {
    await HomeWidget.registerInteractivityCallback(widgetAction);
    await startBackgroundWork();
  }
  final state = AppState(Store(openDb(path)))..start(watchDir: Platform.isLinux ? p.dirname(path) : null);
  runApp(TodoApp(state: state));
  if (Platform.isAndroid) {
    _watchWidgetLaunches(state);
    await _watchReminders(state);
  }
}

/// A widget asked for the diary composer: `todo://diary/new`, optionally
/// `?voice=1` to start listening and `?task=ID` or `?habit=ID` for what the
/// entry is about.
void _openFromWidget(AppState state, Uri? uri) {
  if (uri == null || uri.host != 'diary') return;
  WidgetsBinding.instance.addPostFrameCallback((_) {
    final context = _navigator.currentState?.overlay?.context;
    if (context == null) return;
    final q = uri.queryParameters;
    final habitId = q['habit'];
    showDiaryComposer(
      context,
      task: q['task'] == null ? null : state.store.findTask(q['task']!),
      habit: habitId == null ? null : state.store.habits().where((h) => h.id == habitId).firstOrNull,
      listen: q['voice'] == '1',
    );
  });
  WidgetsBinding.instance.scheduleFrame();
}

Future<void> _watchWidgetLaunches(AppState state) async {
  HomeWidget.widgetClicked.listen((uri) => _openFromWidget(state, uri));
  _openFromWidget(state, await HomeWidget.initiallyLaunchedFromHomeWidget());
}

final _navigator = GlobalKey<NavigatorState>();
final _reminderOpen = <String>{};

/// Opens the full-screen reminder for [r], unless it is already up or the
/// item has been ticked in the meantime.
Future<void> _showReminder(AppState state, Reminder r) async {
  final navigator = _navigator.currentState;
  if (navigator == null) return;
  if (r.isHandled(state.store)) return clearReminder(r);
  if (!_reminderOpen.add(r.key)) return;
  await navigator.push(MaterialPageRoute<void>(fullscreenDialog: true, builder: (_) => ReminderPage(r)));
  _reminderOpen.remove(r.key);
}

/// Shows a reminder when one is tapped or raised full screen by the system,
/// including when that is what started the app.
Future<void> _watchReminders(AppState state) async {
  onReminderOpened = (r) => _showReminder(state, r);
  await initNotifications();
  final launch = await notifications.getNotificationAppLaunchDetails();
  final first = launch?.didNotificationLaunchApp == true
      ? Reminder.fromPayload(launch!.notificationResponse?.payload)
      : null;
  if (first != null) WidgetsBinding.instance.addPostFrameCallback((_) => _showReminder(state, first));
  await requestNotificationPermission(state.store);
}

class TodoApp extends StatelessWidget {
  const TodoApp({super.key, required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) => AppScope(
        state: state,
        child: MaterialApp(
          title: 'Todo',
          navigatorKey: _navigator,
          debugShowCheckedModeBanner: false,
          theme: appTheme(),
          home: const Shell(),
        ),
      );
}

class Shell extends StatefulWidget {
  const Shell({super.key});

  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> {
  int _index = 0;

  static const _pages = [
    (icon: Icons.home_rounded, label: 'Today', page: TodayPage()),
    (icon: Icons.view_agenda_rounded, label: 'Plan', page: PlanPage()),
    (icon: Icons.grid_view_rounded, label: 'Habits', page: HabitsPage()),
    (icon: Icons.timer_rounded, label: 'Focus', page: FocusPage()),
    (icon: Icons.phone_android_rounded, label: 'Screen', page: ScreenPage()),
  ];

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final text = Theme.of(context).textTheme;
    final wide = MediaQuery.sizeOf(context).width >= 720;
    final syncIcon = !app.remote.signedIn
        ? Icons.cloud_off_outlined
        : app.syncError != null
            ? Icons.cloud_off
            : app.syncing
                ? Icons.cloud_sync_outlined
                : Icons.cloud_done_outlined;

    final header = Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 16, 8),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  // The Today page shows its own date, so greet there instead.
                  _index == 0
                      ? switch (DateTime.now().hour) {
                          < 5 => 'Still up',
                          < 12 => 'Good morning',
                          < 17 => 'Good afternoon',
                          _ => 'Good evening',
                        }
                      : prettyDate(today()),
                  style: text.labelLarge?.copyWith(color: AppColors.muted),
                ),
                Text(
                  _pages[_index].label,
                  style: text.headlineMedium?.copyWith(fontWeight: FontWeight.w800, height: 1.1),
                ),
              ],
            ),
          ),
          IconButton.filled(
            tooltip: 'Diary',
            style: IconButton.styleFrom(backgroundColor: AppColors.card, foregroundColor: AppColors.ink),
            icon: const Icon(Icons.edit_note_rounded),
            onPressed: () => Navigator.push(context, MaterialPageRoute<void>(builder: (_) => const DiaryPage())),
          ),
          const SizedBox(width: 8),
          IconButton.filled(
            tooltip: 'Sync',
            style: IconButton.styleFrom(backgroundColor: AppColors.card, foregroundColor: AppColors.ink),
            icon: Icon(syncIcon),
            onPressed: () => Navigator.push(context, MaterialPageRoute<void>(builder: (_) => const SyncPage())),
          ),
        ],
      ),
    );

    final content = Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760),
        child: Column(children: [header, Expanded(child: _pages[_index].page)]),
      ),
    );

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: wide
            ? Row(
                children: [
                  NavigationRail(
                    selectedIndex: _index,
                    onDestinationSelected: (i) => setState(() => _index = i),
                    labelType: NavigationRailLabelType.all,
                    backgroundColor: AppColors.bg,
                    indicatorColor: AppColors.orange,
                    selectedIconTheme: const IconThemeData(color: Colors.white),
                    unselectedIconTheme: const IconThemeData(color: AppColors.muted),
                    destinations: [
                      for (final p in _pages)
                        NavigationRailDestination(icon: Icon(p.icon), label: Text(p.label)),
                    ],
                  ),
                  Expanded(child: content),
                ],
              )
            : content,
      ),
      bottomNavigationBar: wide
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
                child: Container(
                  padding: const EdgeInsets.all(6),
                  decoration: const ShapeDecoration(color: AppColors.card, shape: StadiumBorder()),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      for (final (i, p) in _pages.indexed)
                        _NavItem(
                          key: ValueKey('nav-${p.label}'),
                          icon: p.icon,
                          label: p.label,
                          selected: i == _index,
                          onTap: () => setState(() => _index = i),
                        ),
                    ],
                  ),
                ),
              ),
            ),
    );
  }
}

/// A tab in the floating pill: the selected one widens to show its label.
class _NavItem extends StatelessWidget {
  const _NavItem({
    super.key,
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        selected: selected,
        label: label,
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            padding: EdgeInsets.fromLTRB(4, 4, selected ? 12 : 4, 4),
            decoration: ShapeDecoration(
              color: selected ? AppColors.raised : Colors.transparent,
              shape: const StadiumBorder(),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              spacing: 6,
              children: [
                CircleAvatar(
                  radius: 16,
                  backgroundColor: selected ? AppColors.orange : Colors.transparent,
                  child: Icon(icon, size: 22, color: selected ? Colors.white : AppColors.muted),
                ),
                if (selected)
                  ExcludeSemantics(
                    child: Text(
                      label,
                      style: Theme.of(context).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700),
                    ),
                  ),
              ],
            ),
          ),
        ),
      );
}
