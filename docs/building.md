# Building from source

The [quick start](../README.md#quick-start) installs ready-made programs. Build
from source to change the code, to run on something other than 64-bit Linux,
or to bake your own sync server into the apps.

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

## Requirements

- Linux with GNOME for the desktop pieces (built and used on Ubuntu 26.04, GNOME Shell 50)
- Android 12 or newer for the phone app
- [Flutter](https://docs.flutter.dev/get-started/install/linux) 3.47 or newer. The scripts expect it at `~/development/flutter`
- A free [Supabase](https://supabase.com) project, only if you want sync

## Steps

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

Then `todo init` connects your assistant and sets up sync and a vault, as in
the quick start.

### 3. Your sync server in the apps (optional)

The apps can be told the server on their Sync page. To build it in instead,
copy `config.example.json` to `config.local.json` and fill in your project URL
and publishable key. The install scripts pass it to the build.

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

`install-phone.sh` builds one APK per processor type and installs the one for
the connected phone.

## Development

```bash
(cd packages/core && dart test)
(cd cli && dart analyze && dart test)\n(cd apps/app && flutter analyze && flutter test)
```

After changing a skill in `plugin/skills` or `supabase/schema.sql`, run
`dart run tool/embed_skills.dart` in `cli`: the command carries a copy of
both, and a test fails if they drift.

`apps/app/tool/voice_check_test.dart` runs a recording through the on-device
speech engine without a microphone; the top of the file says how.

## Releasing

Pushing a tag like `v0.2.0` runs `.github/workflows/release.yml`, which builds
the command, the Linux app, the Android app and the GNOME extension and
publishes them as a GitHub Release. The installer and the quick start always
fetch the latest release.

```bash
git tag v0.2.0
git push origin v0.2.0
```

**Sign the Android app with your own key, once.** Without one, each release is
signed with a throwaway key and cannot be installed over the last. Make a key
and keep the file and its password somewhere safe; losing them means users
have to uninstall before they can update.

```bash
keytool -genkey -v -keystore ~/todo-release.jks -keyalg RSA -keysize 2048 -validity 10000 -alias todo
base64 -w0 ~/todo-release.jks   # the value for ANDROID_KEYSTORE_BASE64
```

Add four repository secrets under *Settings > Secrets and variables > Actions*:
`ANDROID_KEYSTORE_BASE64`, `ANDROID_KEYSTORE_PASSWORD`, `ANDROID_KEY_ALIAS`
(`todo` above) and `ANDROID_KEY_PASSWORD`. To sign local builds with the same
key, put the four values in `apps/app/android/key.properties` as `storeFile`,
`storePassword`, `keyAlias` and `keyPassword`.
