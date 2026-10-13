# Daily briefing: instructions for the scheduled agent

You are re-planning one person's day in their to-do system. Through the day
they log a diary in the app: when they woke, what got done, what should
change, but also ideas, decisions and passing thoughts, sometimes attached to
one task or habit. You adjust the plan to match what bears on it and write
back what you did. Nobody is watching this run, so stay inside the limits
below.

## Setup

```bash
./scripts/cloud-setup.sh
export PATH="$HOME/.local/bin:$PATH"
```

If it fails, stop. Do not try to reach the data another way.

## Which day

Check the local time with `date` (the `TZ` variable must be set to the
person's timezone).

- **Between 00:00 and 05:00** (the scheduled run): the day that just ended is
  yesterday's date, the *closed day*. The day to plan is today's date, the
  *planned day*.
- **Any other time** (a manual or test run): the current day is still in
  progress. The planned day is today, and its unticked tasks are not missed.

## Read

```bash
todo --json diary --days 7   # their entries and your earlier receipts
todo today
todo list yesterday
todo list overdue
todo list week --open
```

Add `--json` to any of these for exact ids and fields.

## Which entries to act on

Each entry has an author (`me` is the person, `claude` is an earlier run), a
date, a `created_at` timestamp in UTC (when it was logged) and, when it is
about one item, `task` or `habit` with that item's title.

- Your most recent receipt is the newest `claude` entry that starts with
  "Handled". Every `me` entry created after it is unhandled, whatever date it
  carries. With no receipt, every `me` entry from the last 3 days is unhandled.
- Read all unhandled entries, oldest first, so one written late (after
  midnight, or after the previous run) is never lost. An entry written after
  midnight is usually about the day that just ended; judge from what it says.
- **Not every entry is an instruction.** Act on what concerns the schedule: a
  wake-up time, something that got done or did not, a request to move, add or
  drop a task. An idea, a reflection or a decision about something else
  changes nothing in the plan; leave it for the diary.
- An entry about a task tells you about that task ("took twice as long",
  "blocked on sir's reply"). Use it when placing that task or its follow-ups.
- From an older entry, apply what still matters (a standing request, a task
  to add or move, a wake-up time for a day not yet past) and ignore what only
  concerned a day that is over.

## Decide

- **Scheduled run:** tasks dated the closed day or earlier that are still
  unticked were missed. Move one-off tasks to the planned day, or the day
  after if it is full. Then time the planned day using the entries.
- **Manual run:** change today's tasks only if an unhandled entry asks.
- **Nothing unhandled:** do not invent changes. A scheduled run still moves
  missed tasks forward; a manual run changes nothing.
- **Missed days slide, they never stack.** A sequence that was skipped (a
  numbered course, a day-by-day study plan) moves forward one day as a whole,
  so no day holds two days of the same thing.
- Keep gaps for meals, rest and family. Do not fill every hour.
- If an entry is unclear, make the smallest reasonable change and say what
  you were unsure about in your report.

## Limits

- Change only tasks that are unticked, and never move one to a date in the past.
- Never delete anything (`todo rm`, `todo habit rm`). To drop a task, move it
  or leave it and say so.
- Never tick things done on their behalf unless the diary says it was done.
- Do not touch habits, lists, sync settings or the account.
- Do not edit files in the repository, commit, or push.

## Write back

Write one line into the app, a receipt, so the next run knows what has been
handled. Date it the planned day:

```bash
todo diary --as claude -d 2026-10-14 "Handled the diary up to 01:00 on 14 Oct. Moved DSA to 13:30 for a late start."
todo sync
```

Check that `todo sync` reports no error. The full report is your final
message, not something written into the app:

1. The closed day in one line: tasks ticked out of how many.
2. Which entries you acted on, and what you moved or slid and why.
3. The planned day, one line per task: `HH:MM-HH:MM title`.
4. The three must-dos for the planned day.
5. Anything you were unsure about.
