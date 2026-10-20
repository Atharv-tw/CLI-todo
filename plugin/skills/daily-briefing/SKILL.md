---
name: daily-briefing
description: Plan or re-plan the user's day in their Todo app from what actually happened - what is ticked, when they woke, what their diary says. Use when they ask for a daily briefing, "plan my day", "what should I do today", "re-plan today", or say they woke late, fell behind or want to move things around.
---

# Daily briefing

The user keeps tasks, habits and a diary in the Todo app. A plan made
yesterday rarely survives the morning. Your job is to fit today's plan to the
day they are actually having, in the app, and tell them what it now looks
like.

Everything goes through the `myvault` command; add `--json` for exact ids and
fields. If the Todo tools are connected as an MCP server, the tools of the
same names (`today`, `list_tasks`, `update_task`, `list_diary`) do the same.

## Steps

1. **Read the day.**

   ```bash
   myvault sync                       # skip quietly if there is no sync server
   myvault stats                      # what recent days really looked like
   myvault today
   myvault list overdue
   myvault list due                   # deadlines, soonest first
   myvault --json diary --unprocessed # entries no one has acted on yet
   ```

2. **Read how they like their day.** Run `myvault --json notes status`. If
   `path` is set, read `Rules.md` there (every correction they have made),
   then `Me.md` (their goals and how they like their day planned). Both win
   over the general rules below, and `Rules.md` wins over `Me.md`.
3. **Capture what they committed to.** For each unprocessed entry, every
   "I have to / need to / gotta …" becomes a backlog task linked to the entry
   (`myvault add TITLE -l PROJECT --from ENTRY [--due DATE]`), unless an open
   task already covers it. Then record what became of the entry with
   `myvault diary-outcome ENTRY "..."`. Ideas stay ideas; wants become goals in
   `Me.md`, not tasks.
4. **Work out where the day stands:** the time now, what is ticked, and what
   the diary says about waking and what got done. If you cannot tell when
   their day started and it matters, ask that one question and nothing
   else.
5. **Re-plan** with `myvault edit ID -d DATE -t HH:MM-HH:MM`:
   - Start from now, not from the morning. Never put a task in the past.
   - Protected tasks stay on their day; fixed ones stay at their time. Moving
     one needs `--reason`. A moved task keeps its deadline.
   - Deadlines within a week come before other backlog work. At most five
     newly captured commitments go into one day.
   - Keep the order they like, from when the day starts. A first-thing block
     (a workout) stays first even on a late day. When the day is short, move
     the least important tasks off it; do not squeeze everything in.
   - A skipped sequence (a numbered course, a day-by-day study plan) slides
     forward a day as a whole. Never two days of the same thing on one day.
     When only part of a sequence day was done, tick that part and put the
     rest at the front of the next day of the sequence.
   - Leave gaps for meals, rest and family. Do not fill every hour.
   - Yesterday's unticked project work and one-off tasks go back to the
     backlog, unless their deadline is within a week or they said they
     would do them today.
   - Never change a habit. If one keeps disagreeing with how their days go,
     suggest a change and let them decide.
6. **Check it** with `myvault check-plan` and fix what it reports until the plan
   holds.
7. **Tell them,** briefly: today's plan as `HH:MM-HH:MM title` lines, the
   three things that matter most, the commitments you captured, and what you
   moved and why.
8. **Offer to file the diary** if they have a vault and `vault status`
   reports entries waiting. That is the `file-diary` skill.

## Limits

- Change only unticked tasks. Never delete a task or a habit; to drop
  something, move it or leave it, and say so.
- Never tick something done unless they, or their diary, said it was done.
- Leave habits, lists and sync settings alone.
- If something they wrote is unclear, make the smallest reasonable change and
  say what you were unsure about.
