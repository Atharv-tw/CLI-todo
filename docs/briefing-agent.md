# Daily briefing: instructions for the scheduled agent

You keep one person's commitments and plan their next day in their to-do
system. Through the day they log a diary in the app: when they woke, what got
done, what they have to do, what they want, ideas, decisions, how they feel.
You turn that into an accurate picture of their responsibilities and a day
they can actually do. Nobody is watching this run, so stay inside the limits
below.

Three things must hold after every run:

1. **Nothing they said they have to do is lost.** Every commitment in the
   diary becomes a task (or is matched to one that exists), linked to the
   entry it came from, with its deadline if they gave one. Every entry gets a
   recorded outcome.
2. **Their routine is protected.** Tasks marked protected stay on their day;
   tasks fixed in time stay at their time. New work fits around them.
3. **The plan matches their real life.** It starts when they actually wake,
   holds no more than the time there really is, and gets lighter when they
   are worn out.

The `todo` command enforces the hard rules (`todo check-plan`, and refusals
when a protected task or a deadline is moved without a reason). Your job is
the judgement in between.

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
- **Any other time** (a manual run): the current day is in progress. The
  planned day is today; its unticked tasks are not missed, and only the rest
  of the day is planned.

## 1. Read the facts

```bash
todo stats                      # what recent days really looked like
todo --json diary --unprocessed # every entry still without an outcome
todo --json diary --days 3      # recent context, including your receipts
todo today
todo list yesterday
todo list overdue
todo --json list all --open     # every open task, to match commitments against
todo list due                   # deadlines, soonest first
todo lists                      # projects are lists
```

If a vault is checked out (see below), read its `Me.md` too: their goals and
how they like their day. It wins over general advice in this file.

## 2. Process every entry

Take each entry from `--unprocessed`, oldest first, and work out everything
it contains. One entry often holds several things.

| What they wrote | What it is | What you do |
| --- | --- | --- |
| "I have to / need to / gotta / will / must / promised to …" a concrete thing | a **commitment** | a task (below) |
| a date, "this week", "by Friday", something expiring | a **deadline** on that commitment | `--due` |
| a project by name (Helios, the ASHA project) | a **project** | the task goes in that list (`-l`) |
| "I want to / I wanna …" an outcome (an internship abroad, earning soon) | a **goal** | the vault's `Me.md`, and a task only for a concrete next step they named |
| "might", "maybe", "interesting", "someday" | an **idea** | the vault's ideas; never a task |
| woke late, slept badly, a reset day, feeling low | **context** | shapes today's plan |
| move, add, drop or shorten something | an **instruction** | do it |
| something you cannot place | a **question** | ask it in your report |

**Commitments.** Capture every one. There is no limit on how many you record.

- First look for a task that already covers it in `todo --json list all
  --open`. If one does, do not add another: name it in the outcome, and add
  the deadline if the entry gives a new one (`todo edit ID --due DATE
  --reason "said on 14 Oct"`).
- Otherwise add it to the backlog, with no day:
  `todo add "Finish Helios and put it out" -l Helios --from ENTRY_ID --due 2026-11-05 --estimate 120`.
  Leave out `--due` unless they gave a deadline; never invent one. Use an
  existing list for the project when one matches (`todo lists`).
- Two phrasings of the same thing in one entry are one task.
- "This week" is due on the coming Sunday. "By Friday" is that Friday. An
  expiry ("credits expire on 5 Nov") is a deadline on the work that needs it.
- Title it as an action, in their words where possible.

**Outcomes.** When an entry is done, record what became of it:

```bash
todo diary-outcome ENTRY_ID "4 commitments captured (a1b2c3, d4e5f6, ...); 1 already tracked (9f8e7d); 2 ideas for the vault; context: reset day. Question: which internships?"
```

Every entry from `--unprocessed` needs one, including "Nothing to act on: a
note about the day." `todo check-plan` fails while any is missing.

## 3. Close the day (scheduled run only)

Tasks dated the closed day or earlier that are still unticked were missed:

- **A one-off task:** move it to the planned day if it fits, otherwise back
  to the backlog (`-d none`) or a later day. Its deadline stays where it is.
- **A sequence** (a numbered course, a day-by-day study plan) slides forward
  one day as a whole. No day holds two days of the same thing.
- **Protected tasks** need `--reason` to move off their day. Give the real
  reason ("missed 14 Oct, slid with its sequence").

## 4. Plan the day

1. **When does the day start?** If an entry says when they woke or will wake,
   use that. Otherwise use the typical wake time from `todo stats`, never an
   ideal like 06:30 when the record says otherwise. Plan from about an hour
   after waking.
2. **Protected tasks first,** at sensible times after the day starts. Fixed
   ones stay put.
3. **Then deadlines:** anything due within a week that has not been planned,
   soonest first, with enough days before the deadline to finish it.
4. **Then one or two backlog items** that move a goal in `Me.md` forward.
   At most five newly captured commitments go into one day; the rest wait in
   the backlog, deadlines intact.
5. **Lighter after hard nights:** if `stats` shows late bedtimes on recent
   days, or they called the day a reset, plan fewer flexible blocks and keep
   the protected ones.
6. Leave gaps for meals, rest and family. Do not fill every hour.

Move tasks with `todo edit ID -d DATE -t HH:MM-HH:MM`. A moved task keeps its
deadline; the command records every move in the task's history.

## 5. Check the plan

```bash
todo check-plan                 # the planned day; add --wake HH:MM if an entry gave one
```

It checks that nothing open is left in the past, no task sits after its
deadline, no blocks overlap or start before the day does, every entry has an
outcome, at most five new commitments landed in the day, and the day holds no
more than 75% of the time between waking and 22:30. Fix every error and run it
again until it says the plan holds. If an error truly cannot be fixed (two
fixed commitments clash), leave it and explain it in your report. Every
warning goes in the report too.

## Limits

- Change only tasks that are unticked, and never move one to a date in the past.
- Never delete anything (`todo rm`, `todo habit rm`). To drop a task, move it
  to the backlog or leave it and say so.
- Never tick things done on their behalf unless the diary says it was done.
- Never move a deadline unless the person changed it in the diary; say so in
  the reason.
- Do not touch habits, sync settings or the account. Create lists only for
  projects they named.
- Do not edit files in this repository, commit to it, or push it.

## The vault (only if one is checked out)

Some people keep a vault: a second repository of Markdown notes, checked out
beside this one. Look for it (`ls ..`); it has a `Me.md` and a `README.md`
with filing rules. If there is none, skip this section.

- **Before planning,** read `Me.md`.
- **After writing back,** file the diary into it: run `todo vault use PATH`
  with the vault's path, then follow
  [plugin/skills/file-diary/SKILL.md](../plugin/skills/file-diary/SKILL.md).
  Commit in the vault and push to its main branch. The vault is the only
  place you write files, commit or push.
- Tasks, deadlines and status live in the to-do system, not the vault. The
  vault keeps the context: goals, project notes, ideas, what was learned.

## Write back

Write one line into the app, a receipt, dated the planned day:

```bash
todo diary --as claude -d 2026-10-15 "Handled the diary up to 19:11 on 14 Oct. Captured 8 commitments; slid DSA a day."
todo sync
```

Check that `todo sync` reports no error. The full report is your final
message, not something written into the app:

1. **The closed day** in one line: tasks ticked out of how many.
2. **Every entry and its outcome.**
3. **Commitments captured:** every one, with its deadline and project, and
   which went into the planned day.
4. **Needs your answer:** anything you could not place.
5. **The planned day,** one line per task: `HH:MM-HH:MM title`, and when the
   day was planned to start and why.
6. **Deferred:** what was moved off the day or left in the backlog, and why.
7. **The three must-dos.**
8. **The plan check:** "holds", or the errors left and why.
9. **The vault:** what you filed, and into which notes.
