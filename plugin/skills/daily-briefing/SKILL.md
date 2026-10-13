---
name: daily-briefing
description: Plan or re-plan the user's day in their Todo app from what actually happened - what is ticked, when they woke, what their diary says. Use when they ask for a daily briefing, "plan my day", "what should I do today", "re-plan today", or say they woke late, fell behind or want to move things around.
---

# Daily briefing

The user keeps tasks, habits and a diary in the Todo app. A plan made
yesterday rarely survives the morning. Your job is to fit today's plan to the
day they are actually having, in the app, and tell them what it now looks
like.

Everything goes through the `todo` command; add `--json` for exact ids and
fields. If the Todo tools are connected as an MCP server, the tools of the
same names (`today`, `list_tasks`, `update_task`, `list_diary`) do the same.

## Steps

1. **Read the day.**

   ```bash
   todo sync                    # skip quietly if there is no sync server
   todo today
   todo list overdue
   todo list yesterday
   todo --json diary --days 3
   ```

2. **Read how they like their day.** Run `todo --json vault status`. If
   `path` is set, read `Me.md` there: their goals and how they like their day
   planned. It wins over the general rules below.
3. **Work out where the day stands:** the time now, what is ticked, and what
   the diary says about waking, what got done and what should change. Not
   every diary entry is an instruction; act only on what concerns the
   schedule. If you cannot tell when their day started and it matters, ask
   that one question and nothing else.
4. **Re-plan** with `todo edit ID -d DATE -t HH:MM-HH:MM`:
   - Start from now, not from the morning. Never put a task in the past.
   - Keep the order they like. When the day is short, move the least
     important tasks to tomorrow; do not squeeze everything in.
   - A skipped sequence (a numbered course, a day-by-day study plan) slides
     forward a day as a whole. Never two days of the same thing on one day.
   - Leave gaps for meals, rest and family. Do not fill every hour.
   - Yesterday's unticked one-off tasks come to today, or tomorrow if today
     is full.
5. **Tell them,** briefly: today's plan as `HH:MM-HH:MM title` lines, the
   three things that matter most, and what you moved and why.
6. **Offer to file the diary** if they have a vault and `vault status`
   reports entries waiting. That is the `file-diary` skill.

## Limits

- Change only unticked tasks. Never delete a task or a habit; to drop
  something, move it or leave it, and say so.
- Never tick something done unless they, or their diary, said it was done.
- Leave habits, lists and sync settings alone.
- If something they wrote is unclear, make the smallest reasonable change and
  say what you were unsure about.
