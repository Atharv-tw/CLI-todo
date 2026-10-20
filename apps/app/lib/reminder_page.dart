import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:vault_core/vault_core.dart';

import 'reminders.dart';
import 'state.dart';
import 'theme.dart';

const _device = MethodChannel('todo/device');

/// After a reminder is answered on the lock screen, step back so the lock
/// screen shows again instead of the rest of the app.
Future<void> _leaveIfLocked() async {
  try {
    if (await _device.invokeMethod<bool>('isLocked') == true) await _device.invokeMethod<void>('leave');
  } on MissingPluginException {
    // Not on the phone.
  }
}

/// The full-screen reminder: what to do now, and three answers.
///
/// The phone shows this by itself over the lock screen when a task starts;
/// tapping a reminder notification opens it too.
class ReminderPage extends StatefulWidget {
  const ReminderPage(this.reminder, {super.key});

  final Reminder reminder;

  @override
  State<ReminderPage> createState() => _ReminderPageState();
}

class _ReminderPageState extends State<ReminderPage> {
  // Keeps the clock and the "until" line current while the screen sits there.
  late final Timer _tick = Timer.periodic(const Duration(seconds: 15), (_) => setState(() {}));
  bool _answered = false;

  @override
  void initState() {
    super.initState();
    _tick;
  }

  @override
  void dispose() {
    _tick.cancel();
    super.dispose();
  }

  Future<void> _answer(Future<void> Function(AppState app) act) async {
    if (_answered) return;
    _answered = true;
    final app = AppScope.of(context);
    final navigator = Navigator.of(context);
    await act(app);
    navigator.pop();
    await _leaveIfLocked();
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final text = Theme.of(context).textTheme;
    final r = widget.reminder;
    final about = r.describe(app.store);
    final now = DateTime.now();
    final status = now.isBefore(r.startAt)
        ? 'Starts at ${r.start}'
        : now.isBefore(r.endAt)
            ? 'Now, until ${hm(r.endAt)}'
            : 'Was due at ${r.start}';

    return PopScope(
      // Back is the same as Dismiss.
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _answer((_) => clearReminder(r));
      },
      child: Scaffold(
        backgroundColor: AppColors.bg,
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Top: the time, small, like a lock screen.
                    Text(
                      hm(now),
                      textAlign: TextAlign.center,
                      style: text.displaySmall?.copyWith(
                        fontWeight: FontWeight.w300,
                        color: AppColors.muted,
                        height: 1,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                    Text(
                      prettyDate(today(now)),
                      textAlign: TextAlign.center,
                      style: text.labelLarge?.copyWith(color: AppColors.muted),
                    ),
                    // Middle: the task, centred in whatever room is left.
                    Expanded(
                      child: Center(
                        child: SingleChildScrollView(
                          padding: const EdgeInsets.symmetric(vertical: 20),
                          child: SizedBox(
                            width: double.infinity,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                                  decoration: ShapeDecoration(
                                    color: r.isTask ? AppColors.orange : AppColors.lavender,
                                    shape: const StadiumBorder(),
                                  ),
                                  child: Text(
                                    status,
                                    style: text.labelLarge?.copyWith(
                                      color: r.isTask ? Colors.white : AppColors.onLight,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 18),
                                Text(
                                  r.title,
                                  style: text.headlineLarge?.copyWith(fontWeight: FontWeight.w800, height: 1.15),
                                ),
                                const SizedBox(height: 12),
                                Text(about.summary, style: text.titleMedium?.copyWith(color: AppColors.muted)),
                                if (about.notes != null)
                                  Container(
                                    width: double.infinity,
                                    margin: const EdgeInsets.only(top: 20),
                                    padding: const EdgeInsets.all(16),
                                    decoration: BoxDecoration(
                                      color: AppColors.card,
                                      borderRadius: BorderRadius.circular(20),
                                    ),
                                    child: Text(
                                      about.notes!,
                                      style: text.bodyLarge?.copyWith(color: AppColors.ink, height: 1.4),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                    // Bottom: the answers, where a thumb reaches them.
                    FilledButton.icon(
                      key: const ValueKey('reminder-done'),
                      style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(76),
                        iconSize: 28,
                        textStyle: text.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
                      ),
                      onPressed: () => _answer((app) async {
                        app.change(r.markDone);
                        await clearReminder(r);
                      }),
                      icon: const Icon(Icons.check_rounded),
                      label: const Text('Doing it'),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      spacing: 12,
                      children: [
                        Expanded(
                          flex: 3,
                          child: FilledButton.tonalIcon(
                            key: const ValueKey('reminder-snooze'),
                            style: FilledButton.styleFrom(
                              minimumSize: const Size.fromHeight(64),
                              textStyle: text.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                            ),
                            onPressed: () => _answer((app) => snoozeReminder(app.store, r)),
                            icon: const Icon(Icons.snooze_rounded),
                            label: const Text('Snooze 10 min', maxLines: 1, softWrap: false),
                          ),
                        ),
                        Expanded(
                          flex: 2,
                          child: OutlinedButton(
                            key: const ValueKey('reminder-dismiss'),
                            style: OutlinedButton.styleFrom(
                              minimumSize: const Size.fromHeight(64),
                              foregroundColor: AppColors.ink,
                              side: const BorderSide(color: AppColors.line, width: 1.5),
                              textStyle: text.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                            ),
                            onPressed: () => _answer((_) => clearReminder(r)),
                            child: const Text('Dismiss', maxLines: 1, softWrap: false),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
