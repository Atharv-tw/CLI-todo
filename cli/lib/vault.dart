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
  'log.md': '# Log\n\nOne dated line per change to the vault. Newest first.\n',
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

Most of it is filed for me. I log a diary in the Todo app through the day, by
typing or speaking. A filing agent copies each entry into `raw/` exactly as I
said it, then puts each part where it belongs, following the rules below. I
never have to sort anything. I can also write in any note myself; agents only
ever add.

The memory is mine. No agent copies anything from here into a repository, a
commit, a pull request, a post, an email or any outside service unless I ask
for that piece, and none uses it for work done for other people.

## Who reads what

- **`raw/` is the diary exactly as I said it.** Only filing agents (the
  nightly routine, or an agent running the `file-diary` skill) write it or
  read it. Every other agent stays out of `raw/`, always. What it needs from
  the diary is in `days/` and the notes below, already filed.
- **Every other agent** starts at `INDEX.md`, then reads `Rules.md` and
  `Me.md`, then only the notes its task needs. Never the whole vault.
- **Writing in my name:** read `Voice.md` first.

## What goes where

| Note | What it holds | Order |
| --- | --- | --- |
| `INDEX.md` | A map of every note, one line each. Kept current. | by section |
| `log.md` | One dated line per change to the vault. | newest first |
| `Me.md` | Who I am, my goals, how I like my day planned. | |
| `Rules.md` | Every correction I have made to an agent. Read first. | newest first |
| `Voice.md` | How I write, for anything drafted in my name. | |
| `raw/YYYY-MM-DD.md` | My diary entries, exactly as logged. Filing agents only. | as logged |
| `days/YYYY-MM-DD.md` | What each day held, filed from `raw/`, with links. | as logged |
| `people/<Name>.md` | One note per person I mention: who, and every mention. | oldest first |
| `projects/<Project>/<Project>.md` | The idea: what it is, what it does, why, status. | |
| `projects/<Project>/log.md` | What was done on it, when. | oldest first |
| `projects/<Project>/info.md` | Repo, hosting, stack, links, documents. | |
| `learning/<Area>/<Area>.md` | How I study an area and how far I have got. | oldest first |
| `learning/<Area>/<Topic>.md` | What I have learned about one topic. | oldest first |
| `Decisions.md` | Decisions, each with its date and reason. | newest first |
| `Ideas.md` | Ideas worth keeping, dated. An idea I start on gets a project folder. | newest first |
| `morning/YYYY-MM-DD.md` | The morning page for that day, written overnight. | one per day |
| `weekly/YYYY-Www.md` | The Sunday look back over the week. | one per week |
| `reports/<Kind>/YYYY-MM-DD.md` | Reports other routines write, such as an email check. | one per day |

Tasks, deadlines and status live in the to-do app, not here. Project notes
keep the context; the tasks stay in the app.

## Rules for filing (for filing agents)

1. **Copy every entry into `raw/`** for its day, as `- HH:MM text`, in the
   order logged, with ` (on: its title)` after the time if the entry was
   about a task or habit. Exactly my words: no fixes, no links, nothing
   added.
2. **Then write the day** in `days/YYYY-MM-DD.md`: one line per thing that
   happened or was said, short, in plain words, ending with an arrow to each
   note it was filed into. Fix speech-to-text slips here. Leave out phone
   numbers, addresses and anything private about other people; those stay
   in `raw/`.
3. **Then file each part where it belongs:**
   - a **person** I mention by name: a dated line in `people/<Name>.md`
     (created if new), saying what the mention was, linking the day. People I
     know, not public figures.
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
   - a **correction** to an agent ("that is not a task"): a dated line in
     `Rules.md`, saying where it came from.
4. **Add, never rewrite.** Do not delete or reword what is in a note. If a
   new decision replaces an old one, add the new one and say which it
   replaces. Check the names that exist first, so one topic or person does
   not end up in two notes.
5. **Link** with `[[wikilinks]]`, using paths inside folders
   (`[[projects/Onyx/log|log]]`) because many folders hold a `log.md`.
6. **Keep `INDEX.md` current** when you add a note, and add one line to
   `log.md` for each run: the date, and what changed where.
7. **Say what you filed where**, in a short list, when you are done.

## The morning page

Written each night by the planner into `morning/YYYY-MM-DD.md`, for the day
it plans. The same text is the nightly report. Sections, in this order, each
left out when empty:

1. **The day:** one line per block, `HH:MM–HH:MM title`, and when the day
   starts and why.
2. **Facts:** what is known for sure: yesterday's tasks done out of planned,
   deadlines in the next 7 days, what I said in the diary.
3. **Guesses:** what the planner inferred and could be wrong about.
4. **Done:** what the night run changed: commitments captured, tasks moved,
   notes filed.
5. **Waiting for my yes:** anything it wants to do but will not without me.
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
8. **Three things to focus on next week**, tied to the goals in `Me.md`.

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
- DSA: solved Two Sum in one pass with a dictionary. → [[learning/DSA/Hash maps|Hash maps]]
```

`people/Sam.md`

```markdown
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

`Decisions.md`

```markdown
## 2026-10-13: Park Onyx until the hackathon is over

Why: too many things at once. Project: [[projects/Onyx/Onyx|Onyx]]
```
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

## About this vault

- [[README]]: how it is organised and the filing rules.
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
