---
name: vault-context
description: The user's private second brain, kept by Vault. Use when the task is personal to them - their goals, plans, projects, people they know, what they learned or decided, anything written in their name - to read only the notes the task needs; when a chat produces an answer worth keeping, to save it; and when working in a code folder tied to one of their projects, to log finished work there. Not for reading their personal notes during plain coding work.
---

# Vault context

The user keeps a vault: a private folder of Markdown notes (it opens in
Obsidian) that their diary is filed into every night. It is their memory,
shared by every agent they use. Vault's `myvault` command and its MCP tools
(`search`, `read_note`, `add_note`, `list_projects`, `log_project_work`,
`list_goals`, `morning_page`, `save_notes`) reach it; `myvault --json notes
status` gives its path. The vault's own `README.md` is its schema and wins
over anything here.

Read only what the task needs. Never load the whole vault.

## A personal task: read

1. `Rules.md`: every correction the user has made to an agent. It wins over
   everything, including this skill.
2. `Me.md`: who they are, their goals, how they like their days.
3. `INDEX.md`: a map of every note. Pick the one or two the task needs, or
   `search` for the words, then `read_note` only those.

| Task | Note |
| --- | --- |
| writing in their name | `Voice.md` |
| a project | `projects/<Project>/<Project>.md`, then its `log.md` or `info.md` |
| a person | `people/<Name>.md` |
| what they learned | `learning/<Area>/...` |
| a past decision | `Decisions.md` |
| a past day | `days/YYYY-MM-DD.md` |
| today's plan | `morning_page` (or `myvault morning`) |
| an earlier analysis | `notes/<Title>.md` |

## An answer worth keeping: save it

When a chat produces something they would want again (an analysis, a
comparison, a plan, a recommendation they act on, a summary of a link they
shared), save it without being asked: `add_note` (or `myvault note new TITLE
--body -`), with the question it answers first and the chatter left out,
under a project when it is about one. Then `save_notes`, and tell them in
one line where it went. Small talk and one-off facts are not saved.

## Work in a project's code folder: log it

A folder tied to a project has a `CLAUDE.local.md` saying which (see
`myvault project link`). After each finished piece of work there (a feature
or fix that works, a merged pull request, a release, a deploy, a decision
about the project's direction), call `log_project_work` with one plain
sentence and the pull request or commit, or run `myvault project log NAME
"..." --ref "PR #12"`. Once before the session ends, log anything not yet
logged, then `save_notes`. Results, not process; real numbers only. Do not
read their other notes for this.

## Never

- **Never open `raw/`.** It is the diary word for word, for the filing
  agent only. What you need from it is in `days/` and the notes.
- Never copy anything from the vault into a repository, a commit, a pull
  request, a post, an email or any outside service, unless they ask for that
  piece.
- Never rewrite what the user wrote, or delete anything. Logs and lists are
  append only; project overviews and topic notes are kept current, with a
  `(Superseded YYYY-MM-DD: was "...")` trace when a claim changes.
- Tasks, deadlines and plans live in Vault's store (`myvault` or the MCP
  task tools), not in the notes.
