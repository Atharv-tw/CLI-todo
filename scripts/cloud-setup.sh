#!/usr/bin/env bash
# Prepares a fresh machine (a scheduled cloud session) to use the `todo`
# command against your synced data: installs Dart if needed, builds the CLI,
# signs in and syncs. Needs these environment variables:
#   TODO_SUPABASE_URL, TODO_SUPABASE_KEY   the project (as in config.local.json)
#   TODO_EMAIL, TODO_PASSWORD              the sync account
#   TZ                                     your timezone, e.g. Asia/Kolkata,
#                                          so "today" means your today
set -euo pipefail
cd "$(dirname "$0")/.."

for v in TODO_SUPABASE_URL TODO_SUPABASE_KEY TODO_EMAIL TODO_PASSWORD TZ; do
  [ -n "${!v:-}" ] || { echo "Missing environment variable: $v" >&2; exit 1; }
done

DART_VERSION=3.13.5
if ! command -v dart >/dev/null; then
  if [ ! -x "$HOME/dart-sdk/bin/dart" ]; then
    tmp="$(mktemp -d)"
    curl -fsSL -o "$tmp/dart.zip" \
      "https://storage.googleapis.com/dart-archive/channels/stable/release/$DART_VERSION/sdk/dartsdk-linux-x64-release.zip"
    unzip -q "$tmp/dart.zip" -d "$HOME"
    rm -rf "$tmp"
  fi
  export PATH="$HOME/dart-sdk/bin:$PATH"
fi

(cd cli && dart pub get >/dev/null && dart build cli >/dev/null)
mkdir -p "$HOME/.local/bin"
ln -sf "$PWD/cli/build/cli/linux_x64/bundle/bin/todo" "$HOME/.local/bin/todo"
export PATH="$HOME/.local/bin:$PATH"

todo server "$TODO_SUPABASE_URL" "$TODO_SUPABASE_KEY" >/dev/null
# `todo login` reads the password from standard input when there is no terminal.
printf '%s\n' "$TODO_PASSWORD" | todo login --email "$TODO_EMAIL"
echo "Ready. Use: $HOME/.local/bin/todo (run 'todo sync' after making changes)"
