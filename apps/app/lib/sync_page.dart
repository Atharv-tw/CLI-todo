import 'dart:io';

import 'package:device_calendar_plus/device_calendar_plus.dart';
import 'package:flutter/material.dart';

import 'calendar_sync.dart';
import 'state.dart';

class SyncPage extends StatefulWidget {
  const SyncPage({super.key});

  @override
  State<SyncPage> createState() => _SyncPageState();
}

class _SyncPageState extends State<SyncPage> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  String? _error;
  bool _busy = false;
  bool _filled = false;

  @override
  void dispose() {
    for (final c in [_email, _password]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _signIn(AppState app) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await app.signIn(
        email: _email.text.trim(),
        password: _password.text,
      );
      _password.clear();
    } catch (e) {
      _error = e.toString().startsWith('ClientException') || e.toString().startsWith('SocketException')
          ? 'Could not reach the server. Check your connection.'
          : e.toString();
    }
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final theme = Theme.of(context);
    if (!_filled) {
      _filled = true;
      _email.text = app.remote.email ?? '';
    }

    final List<Widget> children;
    if (app.remote.signedIn) {
      final last = app.lastSync;
      children = [
        Text('Signed in as ${app.remote.email ?? 'your account'}', style: theme.textTheme.titleMedium),
        Text(
          app.syncError ??
              (app.syncing
                  ? 'Syncing…'
                  : last == null
                      ? 'Not synced yet in this session.'
                      : 'Last synced at ${TimeOfDay.fromDateTime(last).format(context)}.'),
          style: TextStyle(color: app.syncError == null ? null : theme.colorScheme.error),
        ),
        Row(
          spacing: 12,
          children: [
            FilledButton.icon(
              icon: const Icon(Icons.sync),
              label: const Text('Sync now'),
              onPressed: app.syncing ? null : app.sync,
            ),
            TextButton(onPressed: app.signOut, child: const Text('Sign out')),
          ],
        ),
        const Text('Signing out keeps everything on this device; it only stops syncing.'),
      ];
    } else if (!app.remote.configured) {
      children = [
        const Text(
          'This build has no sync server. Everything still works on this device. To sync, put your '
          'Supabase project in config.local.json and rebuild (see the README).',
        ),
      ];
    } else {
      children = [
        const Text(
          'Everything works without signing in. Sign in to sync this device with your others.',
        ),
        TextField(
          controller: _email,
          keyboardType: TextInputType.emailAddress,
          autocorrect: false,
          decoration: const InputDecoration(labelText: 'Email'),
        ),
        TextField(
          controller: _password,
          obscureText: true,
          decoration: const InputDecoration(labelText: 'Password'),
          onSubmitted: (_) => _signIn(app),
        ),
        if (_error != null) Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
        Align(
          alignment: Alignment.centerLeft,
          child: FilledButton(
            onPressed: _busy ? null : () => _signIn(app),
            child: Text(_busy ? 'Signing in…' : 'Sign in'),
          ),
        ),
      ];
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Sync')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              for (final c in children) Padding(padding: const EdgeInsets.only(bottom: 16), child: c),
              if (Platform.isAndroid) const _CalendarSection(),
            ],
          ),
        ),
      ),
    );
  }
}

/// Phone only: choose the calendar that timed tasks are mirrored into.
class _CalendarSection extends StatefulWidget {
  const _CalendarSection();

  @override
  State<_CalendarSection> createState() => _CalendarSectionState();
}

class _CalendarSectionState extends State<_CalendarSection> {
  List<Calendar>? _calendars;

  Future<void> _load(CalendarSync sync) async {
    final calendars = await sync.writableCalendars();
    if (mounted) setState(() => _calendars = calendars);
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final theme = Theme.of(context);
    final sync = CalendarSync(app.store);
    final calendars = _calendars;
    if (calendars == null && sync.calendarId != null) _load(sync);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: 12,
      children: [
        const Divider(),
        Text('Calendar', style: theme.textTheme.titleMedium),
        const Text(
          'Tasks with a time appear as events in the calendar you pick, and moving or renaming '
          'one of those events there updates the task. Other events are never touched.',
        ),
        if (calendars == null)
          OutlinedButton(
            onPressed: () => _load(sync),
            child: Text(sync.calendarId == null ? 'Choose a calendar' : 'Loading calendars…'),
          )
        else if (calendars.isEmpty)
          const Text('No calendar available. Allow calendar access for Todo in system settings.')
        else
          RadioGroup<String?>(
            groupValue: calendars.any((c) => c.id == sync.calendarId) ? sync.calendarId : null,
            onChanged: (id) {
              setState(() => sync.calendarId = id);
              app.sync();
            },
            child: Column(
              children: [
                const RadioListTile<String?>(value: null, title: Text('Off')),
                for (final c in calendars)
                  RadioListTile<String?>(
                    value: c.id,
                    title: Text(c.name),
                    subtitle: c.accountName == null ? null : Text(c.accountName!),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}
