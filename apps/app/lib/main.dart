import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:home_widget/home_widget.dart';
import 'package:todo_core/todo_core.dart';

import 'background.dart';
import 'focus_page.dart';
import 'habits_page.dart';
import 'outputs.dart';
import 'plan_page.dart';
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
  requestNotificationPermission();
}

class TodoApp extends StatelessWidget {
  const TodoApp({super.key, required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) => AppScope(
        state: state,
        child: MaterialApp(
          title: 'Todo',
          debugShowCheckedModeBanner: false,
          theme: appTheme(Brightness.light),
          darkTheme: appTheme(Brightness.dark),
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
    (icon: Icons.today, label: 'Today', page: TodayPage()),
    (icon: Icons.view_agenda_outlined, label: 'Plan', page: PlanPage()),
    (icon: Icons.check_circle_outline, label: 'Habits', page: HabitsPage()),
    (icon: Icons.timer_outlined, label: 'Focus', page: FocusPage()),
  ];

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final wide = MediaQuery.sizeOf(context).width >= 720;
    final syncIcon = !app.remote.signedIn
        ? Icons.cloud_off_outlined
        : app.syncError != null
            ? Icons.cloud_off
            : app.syncing
                ? Icons.cloud_sync_outlined
                : Icons.cloud_done_outlined;

    final content = Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760),
        child: _pages[_index].page,
      ),
    );

    return Scaffold(
      appBar: AppBar(
        title: Text(_pages[_index].label),
        actions: [
          IconButton(
            tooltip: 'Sync',
            icon: Icon(syncIcon),
            onPressed: () => Navigator.push(context, MaterialPageRoute<void>(builder: (_) => const SyncPage())),
          ),
        ],
      ),
      body: wide
          ? Row(
              children: [
                NavigationRail(
                  selectedIndex: _index,
                  onDestinationSelected: (i) => setState(() => _index = i),
                  labelType: NavigationRailLabelType.all,
                  backgroundColor: Theme.of(context).scaffoldBackgroundColor,
                  destinations: [
                    for (final p in _pages)
                      NavigationRailDestination(icon: Icon(p.icon), label: Text(p.label)),
                  ],
                ),
                Expanded(child: content),
              ],
            )
          : content,
      bottomNavigationBar: wide
          ? null
          : NavigationBar(
              selectedIndex: _index,
              onDestinationSelected: (i) => setState(() => _index = i),
              destinations: [
                for (final p in _pages) NavigationDestination(icon: Icon(p.icon), label: p.label),
              ],
            ),
    );
  }
}
