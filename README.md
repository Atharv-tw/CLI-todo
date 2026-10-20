# Vault

<img src="assets/logo.svg" alt="Vault logo" width="96">

A private second brain that your agents share. You talk or write to a diary;
Vault turns it into a memory of plain Markdown notes (who you are, your goals,
projects, people, what you learned and decided) and into a plan for your days
built around how you actually live. Claude Code, Codex and any MCP agent read
the same memory and the same plan, so none of them starts from zero.

It runs from a command line (`myvault`), a Linux desktop app, a GNOME
top-bar widget, an Android app with home-screen widgets, and an MCP server.
Everything works offline and syncs through your own Supabase project; your
notes live in your own git repository.

**[Website](https://atharv-tw.github.io/vault-app/)** · [Quick start](#quick-start) · [With an assistant](#with-an-assistant) · [Build from source](docs/building.md)

## Quick start

**1. Install.** On 64-bit Linux, one line. It needs no sudo and builds nothing.

```bash
curl -fsSL https://raw.githubusercontent.com/Atharv-tw/vault-app/main/scripts/install.sh | sh -s -- --app
```

That installs the `myvault` command and the desktop app (leave off `-s -- --app`
for the command alone). For the phone, download the APK from the
[latest release](https://github.com/Atharv-tw/vault-app/releases/latest):
`vault-android-arm64.apk` suits almost every phone from the last several years.

**2. Answer three questions.** The installer ends by running `myvault init`:

| It asks | If you say yes |
| --- | --- |
| Sync between devices? | Walks you through a free Supabase project of your own. |
| Connect Claude Code or Codex? | Your assistant can read and change your tasks, plan your day and file your diary. |
| Keep a vault? | A folder of notes, opened in Obsidian, that your diary is filed into. |

Each is optional, and `myvault init` can be run again to change an answer.

**3. Use it.**

```bash
myvault add Revise unit 2 -d tomorrow -t 18:00-20:45 -l Exams
myvault today
myvault done 5bb889
myvault habit add Read 20 min --time 22:15
myvault focus start
```

`myvault --help` lists everything (`todo` still works as its old name); add
`--json` to any command for machine-readable output. Or ask your assistant: "what is on today?", "I woke
at ten, re-plan my day", "file my diary".

## What it does

- Tasks with optional date, time slot, list, tag and notes
- Daily habits with an optional time of day, shown in the same timeline as tasks
- Habit groups: name habits `5 meals / Breakfast`, `5 meals / Lunch` and they remind separately but show as one habit, done once every step is ticked
- Focus timer (25 minutes by default) with minutes logged per day
- Offline first: each device has a full local copy; sync is pull-then-push, newest edit wins per row
- Diary: write or speak an entry at any time, about anything, optionally attached to a task or habit; each is stamped with when it was logged. A scheduled assistant can read it and re-plan the day
- Screen time on both devices: which apps, for how long, and at what hour of the day (Screen tab, `myvault usage`, and the assistant)
- Reminders when a task starts: sound on the laptop; on the phone a full-screen reminder if it is locked and a banner if it is in use, each with *Doing it* (ticks it) and *Snooze 10 min*
- Two-way calendar on Android: timed tasks become events in a calendar you choose; moving or renaming such an event updates the task

## With an assistant

`myvault mcp` is a tool server (MCP over stdio). Connected, an assistant can use
`today`, `list_tasks`, `add_task`, `update_task`, `set_task_done`,
`delete_task`, `add_habit`, `set_habit_done`, `focus_start`, `focus_stop`,
`screen_time`, `list_diary`, `add_diary_entry`, `mark_diary_filed` and
`vault_status`. Two skills tell it how to do the bigger jobs:
[daily-briefing](plugin/skills/daily-briefing/SKILL.md) and
[file-diary](plugin/skills/file-diary/SKILL.md).

- **Claude Code and Codex:** `myvault init` registers the tool server and
  installs the skills for whichever it finds. By hand:

  ```bash
  claude mcp add --scope user myvault -- myvault mcp
  codex mcp add myvault -- myvault mcp
  ```

- **Claude Code, as a plugin:** inside Claude Code, run
  `/plugin marketplace add Atharv-tw/vault-app` and then
  `/plugin install vault@vault-app`. Use this or `myvault init`, not both.
- **On a schedule, with your laptop off:** a cloud session can re-plan your
  day every night from your diary. See [Diary](#diary).
- **ChatGPT and other chat apps** need a tool server on the internet; this
  one runs on your machine, so they are not supported.

## Sync (optional)

Without sync everything works on one device. To have the same tasks on a
phone and a laptop, they sync through a free [Supabase](https://supabase.com)
project of your own; nobody else holds your data. `myvault init` walks through
it. By hand:

1. Create a Supabase project.
2. Open its SQL editor, paste the output of `myvault schema`, and run it. It is
   safe to run again after an update.
3. Under Authentication, add a user (email and password) for yourself. Turn
   off public sign-ups if you do not want anyone else creating accounts in
   your project.
4. On the laptop: `myvault server https://YOUR-PROJECT.supabase.co sb_publishable_YOUR_KEY`,
   then `myvault login`.
5. In the app: tap the cloud icon, enter the same project URL and key, and
   sign in.

The publishable key is meant to ship in client apps; row-level security in
the schema is what keeps each user's rows private.

## Screen time

Both devices record foreground time per app per hour and sync it like everything else.

- **Laptop:** the GNOME extension notes the focused window every 5 seconds and reports once a minute. Time with the screen locked or no input for 5 minutes is not counted. It needs the GNOME top-bar widget (below).
- **Phone:** open the Screen tab and tap *Open settings* to grant usage access to Vault. The app reads Android's own history whenever it opens (Android keeps about 7 days, so open it at least weekly). The home screen is not counted.
- Read it with `myvault usage`, `myvault usage yesterday`, `myvault usage week`, or ask the assistant (the `screen_time` MCP tool).
- It syncs like everything else. If your server was set up before this existed, run the output of `myvault schema` in its SQL editor again; that adds the `screen_usage` table.

## Diary

The *Diary* tab is where you log anything: an idea, a decision, how the day
went. Write it in the box at the bottom, or tap the mic and say it. Entries
are kept by day with the time they were logged, and sync like everything
else. Today's entries stay open; each day that is over folds into one line
you can open again, ten days at a time.

- **About a task or habit:** a task's sheet has a Diary section; a habit's
  menu has *Add diary entry*; the widget's details card has *Diary note*.
- **Quick capture:** the *Diary* home-screen widget opens the composer already
  listening.
- **Voice** is written down on the device by an open-source Whisper model,
  on the phone and on Linux: no key, no account, no connection, and nothing
  you say leaves the device. The first time you tap the mic, pick a model
  to download (100 to 375 MB, once): one that writes any language, or one
  for mixed Hindi and English in Roman letters. The words appear each time
  you pause. Change the model or language with the button at the top of the
  Diary. On Linux the microphone needs `parecord` (`sudo apt install
  pulseaudio-utils`). On a phone you can use Android's own recogniser
  instead, which needs no download but stops at every pause on some phones.
- **Terminal:** `myvault diary` shows recent entries, `myvault diary Finally got
  hash maps --task 6e495e` adds one, `myvault diary-rm ID` deletes one.

An assistant can act on the diary. On the laptop, Claude reads and writes it
through the MCP server (`list_diary`, `add_diary_entry`). To have it happen on
a schedule without your laptop, run a cloud session daily that follows
[docs/briefing-agent.md](docs/briefing-agent.md); `scripts/cloud-setup.sh`
builds the CLI there and signs in from environment variables. Run just after
midnight, it closes out the day that ended, plans the new one from every
entry written since its last run that bears on the schedule, and leaves a
one-line receipt.

If your sync server was set up before the diary existed, run the output of
`myvault schema` in its SQL editor again. It creates the `diary` table, carrying
over a `briefs` table from an earlier version. Until then everything else
keeps syncing and entries wait on the device.

## Vault (optional)

A vault is a folder of plain Markdown notes that builds into a memory of your
own: each day's log, decisions with their reasons, ideas, what you learned by
topic, a note per project, and your goals. You keep logging the diary as
usual; an assistant files each entry where it belongs, so you never sort
anything. Open the folder in [Obsidian](https://obsidian.md) to read and link
through it. Skip all of this if you only want tasks and a diary.

```
myvault notes init                    # creates ~/Vault with starter notes
myvault notes init ~/Notes/Me         # or somewhere else
myvault notes init --github my-vault  # and keep it in a new private GitHub repo
myvault notes use PATH                # point this device at a vault that exists
myvault notes status                  # where it is, and how much waits to be filed
```

- **The rules live in the vault.** `README.md` there says what goes in which
  note and how each looks. Edit it and the filing follows.
- **Filing is done by your assistant, not by this program,** so there is no AI
  key to set up. Ask it to "file my diary": the steps are in
  [plugin/skills/file-diary/SKILL.md](plugin/skills/file-diary/SKILL.md), and
  the MCP server has `vault_status`, `list_diary` and `mark_diary_filed`. An
  entry is marked once filed and is never filed twice.
- **Nothing is rewritten.** The assistant adds to notes; what you wrote stays.
- **From a scheduled cloud session,** the vault has to be somewhere it can
  reach, which is what `--github` is for: the session clones the private
  repo, files, commits and pushes. Give Claude's GitHub app access to the
  vault repository, add it to the routine as a second repository with pushes
  to its main branch allowed, and let the session use the Write and Edit
  tools; [docs/briefing-agent.md](docs/briefing-agent.md) tells the agent the
  rest. On the laptop, `git pull` in the vault to see what was filed. Reading
  it on a phone needs Obsidian plus a git or sync app.

## GNOME top-bar widget

On GNOME, a widget in the top bar shows today's progress, the running task as
a coloured block and the focus countdown; its menu ticks items and starts a
focus session, and it rings when a task starts. It also records the laptop's
screen time. Download `vault-gnome-extension.zip` from the
[latest release](https://github.com/Atharv-tw/vault-app/releases/latest), then:

```bash
gnome-extensions install vault-gnome-extension.zip
```

Log out and back in, then `gnome-extensions enable myvault@atharv.local`.

## Known limits

- Calendar sync runs on the phone only, so a laptop edit reaches the calendar after the phone next syncs (every 15 minutes in the background).
- Home-screen widgets need Android 12 or newer. In a list widget, tap a row's tick to tick it and its text for a card with the details and actions. Android does not pass a long-press on a widget to the app, so there is no hold gesture.
- On Samsung phones the banner shown while the phone is in use is a one-line pill unless *Settings > Notifications > Notification pop-up style* is set to *Detailed*; the buttons are behind its arrow otherwise.
- The app removes the calendar's own default alert from the events it creates, so a task alerts once, from the app. An event made less than the default lead time before it starts can still alert from the calendar once.
- Reminders respect the phone's ringer mode: vibration on vibrate, nothing on mute or Do Not Disturb.
- Sync resolves conflicts per row, not per field: if two devices edit the same task while offline, the later edit replaces the earlier one.

## Build from source

See [docs/building.md](docs/building.md), which also covers the GNOME top-bar
widget and how releases are made.

## License

MIT. See [LICENSE](LICENSE).
