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
  'Me.md': _me,
  'Decisions.md': '# Decisions\n\nNewest first. Each one: the date, the decision in a line, and why.\n',
  'Ideas.md': '# Ideas\n\nNewest first. Each one: the date and the idea, in my own words.\n',
  'Daily/.gitkeep': '',
  'Learning/.gitkeep': '',
  'Projects/.gitkeep': '',
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

const _readme = '''
# My vault

A memory of my own: what I am working towards, what I decided and why, what I
learned, and how each day went. It is a folder of plain Markdown notes. Open
it in Obsidian, or in any editor.

Most of it is filed for me. I log a diary in the Todo app through the day, by
typing or speaking. An assistant reads the new entries and puts each part
where it belongs, following the rules below. I never have to sort anything.
I can also write in any note myself; the assistant only ever adds.

## What goes where

| Note | What it holds | Order |
| --- | --- | --- |
| `Me.md` | Who I am, my goals, how I like my day planned. Changes rarely. | |
| `Daily/YYYY-MM-DD.md` | One note per day: everything I logged, with times. | as logged |
| `Decisions.md` | Decisions, each with its date and reason. | newest first |
| `Ideas.md` | Ideas worth keeping, dated. | newest first |
| `Learning/<Topic>.md` | What I have learned about one topic. | oldest first |
| `Projects/<Project>.md` | One note per project: what it is, and a log. | oldest first |

## Rules for filing (for the assistant)

1. **Every entry goes into its day's note** in `Daily/`, as `- HH:MM text`,
   in the order logged. If the entry was about a task or habit, add
   ` (on: its title)`. Keep my words. Fix only obvious speech-to-text slips;
   never tidy my meaning.
2. **Then file it further only if it clearly is one of these:**
   - a **decision**: `Decisions.md`, with the decision in a line and the
     reason if I gave one.
   - an **idea**: `Ideas.md`.
   - something I **learned**: that topic's note in `Learning/`. One topic per
     note, named plainly (`Hash maps.md`, `Backpropagation.md`). Write the
     point itself, not that I learned it.
   - progress, a problem or a note on a **project**: `Projects/<Project>.md`,
     under `## Log`.
   - a **goal**, or a change to how I want my days: `Me.md`, but only when I
     stated it as a goal or a rule. A wish in passing is not a goal.
3. **Most entries are just the day.** Leave those in `Daily/` only. When in
   doubt, do not file further.
4. **Link notes** with `[[wikilinks]]`. A line in `Daily/` ends with an arrow
   to each note it was filed into. A decision or idea about a project links
   the project.
5. **Add, never rewrite.** Do not delete or reword what is already in a note.
   If a new decision replaces an old one, add the new one and say which it
   replaces. Create a note when it does not exist yet; check the names that
   exist first, so one topic does not end up in two notes.
6. **Say what you filed where**, in a short list, when you are done.

## How each note looks

`Daily/2026-10-13.md`

```markdown
# Tue 13 Oct 2026

- 09:10 Woke up late, felt slow till lunch
- 13:45 Solved it with a dictionary in one pass (on: DSA: Two Sum) → [[Hash maps]]
- 21:30 Decided to park Onyx until the hackathon is over → [[Decisions]], [[Onyx]]
```

`Decisions.md`

```markdown
## 2026-10-13: Park Onyx until the hackathon is over

Why: too many things at once. Project: [[Onyx]]
```

`Ideas.md`

```markdown
- 2026-10-13: A browser extension that turns any lecture tab into flashcards
```

`Learning/Hash maps.md`

```markdown
# Hash maps

## 2026-10-13

- Lookup is O(1) because the hash picks the bucket directly.
```

`Projects/Onyx.md`

```markdown
# Onyx

## Log

- 2026-10-13: Parked until the hackathon is over. See [[Decisions]].
```

`Me.md`: add a goal as one line under Goals, with the date in brackets.
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
