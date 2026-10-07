# CLI todo

<img src="assets/logo.svg" alt="CLI todo logo" width="96">

A personal to-do system: tasks, daily habits and focus timers in one store,
reachable from a command line, a Linux desktop app, a GNOME top-bar widget, an
Android app with home-screen widgets, and an MCP server so an AI assistant can
read and edit your tasks. Everything works offline and syncs through your own
Supabase project when online.

## What is in here

| Path | What it is |
| --- | --- |
| `packages/core` | Pure Dart: SQLite store, sync engine, Supabase client |
| `cli` | The `todo` command, including `todo mcp` (MCP server over stdio) |
| `apps/app` | Flutter app for Linux desktop and Android |
| `apps/app/android` | Android home-screen widgets (Today, Habits, Focus) |
| `gnome-extension` | GNOME Shell top-bar widget |
| `supabase/schema.sql` | Server tables, row-level security, last-write-wins trigger |
| `scripts` | Toolchain setup and install scripts |

Features:

- Tasks with optional date, time slot, list, tag and notes
- Daily habits with an optional time of day, shown in the same timeline as tasks
- Focus timer (25 minutes by default) with minutes logged per day
- Offline first: each device has a full local copy; sync is pull-then-push, newest edit wins per row
- Screen time on both devices: which apps, for how long, and at what hour of the day (Screen tab, `todo usage`, and the assistant)
- Reminders when a task starts: sound on the laptop, sound or vibration and a lock-screen alert on the phone
- Two-way calendar on Android: timed tasks become events in a calendar you choose; moving or renaming such an event updates the task

## Requirements

- Linux with GNOME for the desktop pieces (built and used on Ubuntu 26.04, GNOME Shell 50)
- Android 12 or newer for the phone app
- [Flutter](https://docs.flutter.dev/get-started/install/linux) 3.47 or newer. The scripts expect it at `~/development/flutter`
- A free [Supabase](https://supabase.com) project, only if you want sync

## Setup

### 1. Toolchain

With Flutter unpacked at `~/development/flutter`:

```bash
./scripts/setup-toolchain.sh
```

This installs the Linux build tools and JDK 17 with apt (asks for sudo),
downloads the Android command-line tools to `~/Android/Sdk`, and shows the
Android licences for you to accept. Then install the Android pieces Flutter
builds against:

```bash
~/Android/Sdk/cmdline-tools/latest/bin/sdkmanager "platforms;android-36" "build-tools;36.0.0" "ndk;28.2.13676358"
```

### 2. The `todo` command

```bash
./scripts/install-cli.sh
```

Installs to `~/.local/bin/todo`. Data lives in `~/.local/share/todo/todo.db`
(override with the `TODO_DB` environment variable).

```bash
todo add Revise unit 2 -d tomorrow -t 18:00-20:45 -l Exams --tag "Exam prep"
todo today
todo done 5bb889
todo habit add Read 20 min --time 22:15
todo focus start
```

`todo --help` lists everything; add `--json` to any command for machine-readable output.

### 3. Sync (optional)

1. Create a Supabase project.
2. Open its SQL editor, paste `supabase/schema.sql`, and run it.
3. Under Authentication, add a user (email and password) for yourself. Turn off public sign-ups if you do not want anyone else creating accounts in your project.
4. Point the laptop at the project and sign in:

```bash
todo server https://YOUR-PROJECT.supabase.co sb_publishable_YOUR_KEY
todo login
```

5. For the app builds, copy `config.example.json` to `config.local.json` and fill in the same two values. The install scripts pass it to the build.

The publishable key is meant to ship in client apps; row-level security in
`schema.sql` is what keeps each user's rows private.

### 4. Desktop app

```bash
./scripts/install-desktop.sh
```

Adds "Todo" to the application grid. It shares the database with the CLI.

### 5. GNOME top-bar widget

```bash
ln -s "$PWD/gnome-extension/todo@atharv.local" ~/.local/share/gnome-shell/extensions/
```

Log out and back in, then:

```bash
gnome-extensions enable todo@atharv.local
```

It shows today's progress, the running task as a coloured block, and the focus
countdown; the menu lets you tick items and start a focus session. It rings
when a task starts.

### 6. Android app

Enable USB debugging on the phone, plug it in, then:

```bash
./scripts/install-phone.sh
```

In the app: tap the cloud icon to sign in and to choose the calendar for timed
tasks. Add the widgets from the home screen's widget picker. Exempt the app
from battery optimisation if background sync is slow.

### 7. MCP server (optional)

`todo mcp` speaks MCP over stdio. For Claude Code, copy `.mcp.example.json` to
`.mcp.json` and fix the path. Tools: `today`, `list_tasks`, `add_task`,
`update_task`, `set_task_done`, `delete_task`, `add_habit`, `set_habit_done`,
`focus_start`, `focus_stop`.

## Development

```bash
(cd packages/core && dart test)
(cd apps/app && flutter test)
```

## Known limits

- Calendar sync runs on the phone only, so a laptop edit reaches the calendar after the phone next syncs (every 15 minutes in the background).
- Home-screen widgets need Android 12 or newer.
- Reminders respect the phone's ringer mode: vibration on vibrate, nothing on mute or Do Not Disturb.
- Sync resolves conflicts per row, not per field: if two devices edit the same task while offline, the later edit replaces the earlier one.

## Screen time

Both devices record foreground time per app per hour and sync it like everything else.

- **Laptop:** the GNOME extension notes the focused window every 5 seconds and reports once a minute. Time with the screen locked or no input for 5 minutes is not counted. After pulling this update, log out and back in once so GNOME reloads the extension.
- **Phone:** open the Screen tab and tap *Open settings* to grant usage access to Todo. The app reads Android's own history whenever it opens (Android keeps about 7 days, so open it at least weekly). The home screen is not counted.
- Read it with `todo usage`, `todo usage yesterday`, `todo usage week`, or ask the assistant (the `screen_time` MCP tool).
- To sync it, run the updated `supabase/schema.sql` once; it adds the `screen_usage` table.

## License

MIT. See [LICENSE](LICENSE).
