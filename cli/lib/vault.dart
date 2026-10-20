import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:todo_core/todo_core.dart';

/// Where this device keeps the vault. Stored locally and never synced: the
/// same vault sits at a different path on each machine.
const vaultPathKey = 'vault_path';

String defaultVaultPath() => p.join(Platform.environment['HOME'] ?? '.', 'Vault');

/// The vault's folder on this device, or null if none has been set up.
String? vaultPath(Store store) => store.getMeta(vaultPathKey);

/// The starter notes. An existing file is never overwritten, so running
/// `todo vault init` on a vault that is already in use only adds what is
/// missing.
const vaultFiles = <String, String>{
  'README.md': _readme,
  'INDEX.md': _index,
  'log.md': _log,
  'CLAUDE.md': _agents,
  'AGENTS.md': _agents,
  'Me.md': _me,
  'Rules.md': _rules,
  'Voice.md': _voice,
  'Decisions.md': '# Decisions\n\nNewest first. Each one: the date, the decision in a line, and why.\n',
  'Ideas.md': '# Ideas\n\nNewest first. Each one: the date and the idea, in my own words.\n',
  'raw/.gitkeep': '',
  'days/.gitkeep': '',
  'people/.gitkeep': '',
  'projects/.gitkeep': '',
  'learning/.gitkeep': '',
  'notes/.gitkeep': '',
  'morning/.gitkeep': '',
  'weekly/.gitkeep': '',
  '.gitignore': '.obsidian/workspace*\n.obsidian/cache\n.trash/\n',
};

/// Creates the folder and any starter note that is not there yet. Returns
/// the relative paths it wrote.
List<String> scaffoldVault(String path) {
  final written = <String>[];
  for (final entry in vaultFiles.entries) {
    final file = File(p.join(path, entry.key));
    if (file.existsSync()) continue;
    file
      ..createSync(recursive: true)
      ..writeAsStringSync(entry.value);
    written.add(entry.key);
  }
  return written;
}

/// What `todo vault status` reports.
Map<String, Object?> vaultStatus(Store store) {
  final path = vaultPath(store);
  final exists = path != null && Directory(path).existsSync();
  String? remote;
  if (exists && Directory(p.join(path, '.git')).existsSync()) {
    final r = Process.runSync('git', ['-C', path, 'remote', 'get-url', 'origin']);
    if (r.exitCode == 0) remote = (r.stdout as String).trim();
  }
  return {
    'path': path,
    'exists': exists,
    'git': exists && Directory(p.join(path, '.git')).existsSync(),
    'remote': remote,
    'unfiled': store.diary(author: DiaryEntry.me, unfiledOnly: true).length,
  };
}

/// Puts the vault under git and, when the GitHub CLI is signed in, into a new
/// private repository. Returns lines saying what happened.
List<String> vaultToGitHub(String path, String repo) {
  ProcessResult git(List<String> args) => Process.runSync('git', ['-C', path, ...args]);
  try {
    if (!Directory('$path/.git').existsSync()) git(['init', '-q', '-b', 'main']);
    git(['add', '-A']);
    if ((git(['status', '--porcelain']).stdout as String).trim().isNotEmpty) {
      git(['commit', '-q', '-m', 'Start the vault']);
    }
  } on ProcessException {
    return ['git is not installed, so the vault was not put under version control.'];
  }
  if (git(['remote', 'get-url', 'origin']).exitCode == 0) {
    return ['It already has a remote; left that as it is.'];
  }
  final manual = [
    'To put it on GitHub yourself: create an empty private repository called "$repo", then run',
    '  git -C "$path" remote add origin https://github.com/YOU/$repo.git',
    '  git -C "$path" push -u origin main',
  ];
  try {
    if (Process.runSync('gh', ['auth', 'status']).exitCode != 0) {
      return ['The GitHub CLI is not signed in (run: gh auth login).', ...manual];
    }
    final made = Process.runSync('gh', [
      'repo',
      'create',
      repo,
      '--private',
      '--source',
      path,
      '--remote',
      'origin',
      '--push',
    ]);
    if (made.exitCode != 0) return ['GitHub said: ${(made.stderr as String).trim()}', ...manual];
    return ['Pushed to a new private GitHub repository: ${(made.stdout as String).trim().split('\n').first}'];
  } on ProcessException {
    return ['The GitHub CLI (gh) is not installed.', ...manual];
  }
}

const _readme = '''
# My vault

A memory of my own: what I am working towards, who I work with, what I am
building, what I decided and why, what I learned, and how each day went. It
is a folder of plain Markdown notes. Open it in Obsidian, or in any editor.

This file is the schema: every agent that reads or writes this vault follows
it, and it wins over anything another file says about the vault's layout.
`CLAUDE.md` and `AGENTS.md` here point to it, so an agent opened in this
folder finds it on its own.

The memory is mine. No agent copies anything from here into a repository, a
commit, a pull request, a post, an email or any outside service unless I ask
for that piece, and none uses it for work done for other people.

## Three layers

1. **Sources**, never changed: `raw/` (my diary, word for word) and anything
   I write myself (`Me.md`, my own lines in any note).
2. **The wiki**, written and kept current by agents: `days/`, `people/`,
   `projects/`, `learning/`, `notes/`, `Decisions.md`, `Ideas.md`,
   `Rules.md`, `Voice.md`, the pages in `morning/` and `weekly/`.
3. **The schema**: this file.

## Who reads what

- **`raw/` is the diary exactly as I said it.** Only filing agents (the
  nightly routine, or an agent running the `file-diary` skill) write it or
  read it. Every other agent stays out of `raw/`, always, and no note links
  into it. What others need from the diary is in `days/` and the notes.
- **Every other agent** starts at `INDEX.md`, then reads `Rules.md` and
  `Me.md`, then only the notes its task needs. Never the whole vault.
- **Writing in my name:** read `Voice.md` first.

## What goes where

| Note | What it holds | Order |
| --- | --- | --- |
| `INDEX.md` | A map of every note, one line each. Kept current. | by section |
| `log.md` | One line per change to the vault, in a fixed format. | oldest first, append only |
| `Me.md` | Who I am, my goals, how I like my day planned. | |
| `Rules.md` | Every correction I have made to an agent. Read first. | newest first |
| `Voice.md` | How I write, for anything drafted in my name. | |
| `raw/YYYY-MM-DD.md` | My diary entries, exactly as logged. Filing agents only. | as logged |
| `days/YYYY-MM-DD.md` | What each day held, filed from `raw/`, with links. | as logged |
| `people/<Name>.md` | One note per person I mention: who, and every mention. | oldest first |
| `projects/<Project>/<Project>.md` | The idea: what it is, what it does, why, status. Kept current. | |
| `projects/<Project>/log.md` | What was done on it, when. | oldest first |
| `projects/<Project>/info.md` | Repo, hosting, stack, links, documents. Kept current. | |
| `learning/<Area>/<Area>.md` | How I study an area and how far I have got. | oldest first |
| `learning/<Area>/<Topic>.md` | What I understand about one topic. Kept current. | |
| `notes/<Title>.md` | Answers worth keeping from chats, and summaries of things I shared (articles, gists, videos). | one per note |
| `Decisions.md` | Decisions, each with its date and reason. | newest first |
| `Ideas.md` | Ideas worth keeping, dated. An idea I start on gets a project folder. | newest first |
| `morning/YYYY-MM-DD.md` | The morning page for that day, written overnight. | one per day |
| `weekly/YYYY-Www.md` | The Sunday look back over the week. | one per week |
| `reports/<Kind>/YYYY-MM-DD.md` | Reports other routines write, such as an email check. | one per day |

Tasks, deadlines and status live in the to-do app, not here. Project notes
keep the context; the tasks stay in the app.

## Ingest: new material comes in

Sources arrive four ways. Each is filed by the rules below.

- **My diary**, every night, by the nightly routine.
- **Work in a project folder**: an agent working in one of my project folders
  logs each finished piece of work in that project's `log.md`, as a dated
  line with the pull request or commit.
- **Past chats**: a chat that happened before this vault, read once and filed.
- **Something I share in a chat** (a link, an article, a video): a page in
  `notes/` with its source, what it says in a few lines, and what it means
  for me or my projects, with links.

### Rules for filing the diary

1. **Copy every entry into `raw/`** for its day, as `- HH:MM text`, in the
   order logged, with ` (on: its title)` after the time if the entry was
   about a task or habit. Exactly my words: no fixes, no links, nothing
   added.
2. **Then write the day** in `days/YYYY-MM-DD.md`: one line per thing that
   happened or was said, short, in plain words, ending with an arrow to each
   note it was filed into. Fix speech-to-text slips here. Leave out phone numbers, addresses and anything private about
   other people; those stay in `raw/`.
3. **Then file each part where it belongs:**
   - a **person** I mention by name: a dated line in `people/<Name>.md`
     (created if new), saying what the mention was, linking the day. People I
     know, not public figures. Use the name I use for them.
   - a **project**, even in passing: a dated line in
     `projects/<Project>/log.md`. Update `<Project>.md` when I say what it
     is, what it does or where it stands, and `info.md` when I mention a
     repo, a host, a stack or a document. Create the folder with all three
     files the first time.
   - something I **learned**: the topic's note under `learning/<Area>/`
     (`learning/DSA/Hash maps.md`). Write the point itself, not that I
     learned it. Progress through a course or problem set goes in
     `learning/<Area>/<Area>.md`.
   - a **decision**: `Decisions.md`, with the reason if I gave one.
   - an **idea**: `Ideas.md`.
   - a **goal**, or a change to how I want my days: `Me.md`, only when I
     stated it as a goal or a rule. A wish in passing is not a goal.
   - a **correction** to an agent ("that is not a task"): a dated line in `Rules.md`, saying where it
     came from.
4. **Check the names that exist first** (`INDEX.md`), so one topic or person
   does not end up in two notes. Do not guess how projects, people or
   companies relate; ask (see `Rules.md`).

## Query: an answer worth keeping

When a chat produces something I would want again (an analysis, a
comparison, a plan, a recommendation I acted on, a map of options), file it:

- about one project: a section in that project's `<Project>.md`, or a note
  in its folder (`projects/<Project>/<Topic>.md`);
- otherwise: `notes/<Title>.md`.

Each such note starts with frontmatter (below), says in its first line what
question it answers, keeps the substance and drops the chatter, and links
the projects, people and notes it touches. Add it to `INDEX.md`. Small
talk, one-off facts and answers that only mattered that day are not filed.

## Editing: what may change

- **Never changed:** `raw/`, and anything I wrote myself. If I wrote it, it
  stays as I wrote it.
- **Append only:** every `log.md`, the mention lists in `people/`,
  `Decisions.md`, `Ideas.md`, `Rules.md`. To replace an old line, add a new
  one that says which it replaces.
- **Kept current:** project overviews and `info.md`, topic notes, `notes/`,
  `INDEX.md`. Agents rewrite these so they say what is true now. When new
  information contradicts an old claim, change the claim and leave a trace
  right there: `(Superseded 2026-10-20: was "Repo: none yet".)`. Git keeps
  every older version.
- **Frontmatter**, at the top of every project overview, person and note:

  ```yaml
  ---
  type: project        # project | person | note | source | learning
  status: building     # projects: building | built | paused | role
  updated: 2026-10-20  # the last day its content changed
  ---
  ```

  Update `updated` whenever the page's content changes.

## Lint: keeping it healthy

- **Every Sunday**, the weekly run checks the vault and writes what it found
  under "Vault health" in the weekly page, fixing what is safe to fix:
  - `todo vault lint` first: broken links, links into `raw/`, notes missing
    from `INDEX.md`, pages nothing links to, frontmatter missing or stale,
    days and raw notes that do not match, `log.md` lines out of format.
  - then by reading: claims that contradict each other, statuses that are
    stale, things mentioned on several pages that deserve their own page,
    and questions worth asking me.
- Contradictions it cannot settle go under "Waiting for my yes", never
  guessed.

## `log.md` format

One line per change, appended at the end:

```
- [YYYY-MM-DD] op | what changed, and where
```

`op` is one of: `ingest` (diary, past chat, something shared), `work`
(project work logged), `query` (an answer filed), `lint` (a health check),
`fix` (a correction), `setup` (a change to the vault's layout or rules).
`grep "] ingest |" log.md | tail` shows the latest of a kind.

## The morning page

Written each night by the planner into `morning/YYYY-MM-DD.md`, for the day
it plans. The same text is the nightly report. Sections, in this order, each
left out when empty:

1. **The day:** one line per block, `HH:MM–HH:MM title`, and when the day
   starts and why.
2. **Facts:** what is known for sure: yesterday's tasks done out of planned,
   deadlines in the next 7 days, what I said in the diary.
3. **Guesses:** what the planner inferred and could be wrong about, such as
   the wake time when I gave none, or why something moved.
4. **Done:** what the night run changed: commitments captured, tasks moved,
   notes filed.
5. **Waiting for my yes:** anything it wants to do but will not without me,
   like changing a habit's time or dropping a task.
6. **Open questions.**
7. **Reports:** a short summary of the newest note in each `reports/`
   folder, saying how old it is if it is not from today.

## The weekly page

Written on the night before Sunday into `weekly/YYYY-Www.md` (ISO week):

1. **Decided:** every decision from the week, with a link.
2. **Said and not done:** commitments from the week still open, oldest
   first, with their deadlines.
3. **Projects:** each project with no log line and no task done this week is
   called stalled.
4. **People:** anyone I said I would get back to, and have not.
5. **Routines:** how my regular blocks and habits really went.
6. **Plans vs real days:** tasks done out of planned, the usual wake and
   sleep times, and what the planner should change.
7. **Rules added** this week.
8. **Vault health:** what the lint found and fixed, and what waits for me.
9. **Three things to focus on next week**, tied to the goals in `Me.md`.

## How each note looks

`raw/2026-10-13.md`

```markdown
# Tue 13 Oct 2026

- 09:10 woke up late felt slow till lunch
- 13:45 (on: DSA: Two Sum) solved it with a dictionary in one pass
```

`days/2026-10-13.md`

```markdown
# Tue 13 Oct 2026

- Woke late; slow until lunch.
- DSA: solved Two Sum in one pass with a dictionary. → [[learning/DSA/DSA|DSA]], [[learning/DSA/Hash maps|Hash maps]]
```

`people/Sam.md`

```markdown
---
type: person
updated: 2026-10-13
---
# Sam

**Who:** my lab partner.

## Mentions

- 2026-10-13: Agreed to split the report. ([[days/2026-10-13]])
```

`projects/Onyx/log.md`

```markdown
# Onyx: log

- 2026-10-13: Parked until the hackathon is over. See [[Decisions]]. ([[days/2026-10-13]])
```

`notes/Which course first.md`

```markdown
---
type: note
updated: 2026-10-18
---
# Which course first

Which course to take first, and why. Answer: ...
```

`log.md`

```markdown
- [2026-10-13] ingest | diary 13 Oct: days/2026-10-13, people/Sam, learning/DSA/DSA
```
''';

const _log = '''
# Log

One line per change to the vault, oldest first, appended at the end.
Format: `- [YYYY-MM-DD] op | what changed, and where` (see README.md).
''';

const _agents = '''
# For any agent working in this vault

This is a private memory. Before doing anything here, read `README.md`: it
is the schema (layout, who may read what, how to ingest, file answers, edit
and lint). Then `Rules.md`, then `Me.md`.

- Never open `raw/` unless you are the filing agent filing the diary.
- Never copy anything from here into a repository, a post or any outside
  service unless the owner asks for that piece.
- Every change ends with a line in `log.md` in its format, then commit and
  push if the vault is a git repository.
''';

const _index = '''
# Index

Start here. One line per note; open only what the task needs. `raw/` is not
listed: it is for filing agents only (see [[README]]).

## About me

- [[Rules]]: every correction I have made. Read first.
- [[Me]]: goals, how I like my day planned, things to know.
- [[Voice]]: how I write, for anything drafted in my name.

## Projects

## People

## Learning

## Thinking

- [[Decisions]]: what I decided and why.
- [[Ideas]]: ideas worth keeping.

## Notes

## About this vault

- [[README]]: the schema: layout, who reads what, ingest, query, edit, lint.
- [[log]]: one line per change.
''';

const _rules = '''
# Rules

Every correction I make to an agent ends up here, one line each, so the same
mistake does not happen twice. Every agent reads this note before it plans,
files or writes anything for me. Newest first: the date, the rule in one
sentence, and where it came from. Never delete a rule; if one replaces
another, add the new one and say which it replaces.
''';

const _voice = '''
# Voice

How I sound, for anything an agent drafts in my name: posts, emails,
messages. Add to it whenever I correct a draft.

## How I write

- (Short or long sentences, formal or casual, words I use or avoid.)
''';

const _me = '''
# Me

## Goals

- (What you are working towards. One line each.)

## How I like my day planned

- Wake up:
- Asleep by:
- Blocks, in the order I like them:
- Never schedule:

## Things the assistant should know

- (Anything that helps it plan or file for you: who people are, what your
  projects are called, words you use.)
''';
