# For coding agents working on this repository

Vault: a private second brain that a person's agents share. One local SQLite
store (diary, tasks, habits, plans) reached by a CLI (`myvault`), an MCP
server, a Flutter app (Android and Linux) and a GNOME extension, with optional
sync through the user's own Supabase project; and a vault of Markdown notes
the user owns, kept by agents. `README.md` has the full tour.

## Layout

| Path | What it is |
| --- | --- |
| `packages/core` | Pure Dart: store, migrations, sync engine. No Flutter. |
| `cli` | The `myvault` command (`bin/myvault.dart`), its MCP server (`lib/mcp.dart`), the second-brain operations on the vault (`lib/brain.dart`), the vault template (`lib/vault.dart`) and its lint (`lib/vault_lint.dart`). |
| `apps/app` | Flutter app. `android/` holds the home-screen widgets (Kotlin). |
| `gnome-extension` | GNOME Shell top-bar widget (GJS). |
| `plugin` | Claude Code plugin: skills and the MCP server entry. Codex reads the same `SKILL.md` files. |
| `supabase/schema.sql` | Server tables. Must stay safe to run again on an existing project. |
| `site` | The website, plain HTML and CSS. |

## Build and test

Flutter (which brings Dart) is expected at `~/development/flutter/bin`.

```bash
(cd packages/core && dart test)
(cd cli && dart analyze && dart test)
(cd apps/app && flutter analyze && flutter test)
```

Run all three before saying a change is done. `scripts/install-cli.sh`,
`install-desktop.sh` and `install-phone.sh` build and install each piece.

## Conventions

- A schema change is a new entry at the end of `migrations` in
  `packages/core/lib/src/db.dart`, mirrored in `supabase/schema.sql` in a way
  that is safe to re-run. Never edit an earlier migration.
- A synced table is listed in `syncedTables`, has `updated_at`, `deleted_at`
  and `dirty`, and deletes by tombstone.
- Every CLI command prints text by default and JSON under `--json`. A command
  an assistant needs also gets an MCP tool in `cli/lib/mcp.dart`.
- Doc comments say what a thing is for, not how it got that way.
- Text the user reads is plain English: no jargon, no exclamation marks.
- Skills in `plugin/skills` are embedded in the CLI by
  `dart run tool/embed_skills.dart` (in `cli`); a test fails if they drift.
- Never commit `config.local.json`, `.mcp.json`, a database or an APK.
