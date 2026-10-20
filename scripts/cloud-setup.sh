#!/usr/bin/env bash
# Prepares a fresh machine (a scheduled cloud session) to use the `myvault`
# command against your synced data: installs Dart if needed, builds the CLI,
# signs in and syncs. Needs these environment variables (the older TODO_*
# names work too):
#   MYVAULT_SUPABASE_URL, MYVAULT_SUPABASE_KEY   the project (as in config.local.json)
#   MYVAULT_EMAIL, MYVAULT_PASSWORD              the sync account
#   TZ                                           your timezone, e.g. Asia/Kolkata,
#                                                so "today" means your today
set -euo pipefail
cd "$(dirname "$0")/.."

for v in SUPABASE_URL SUPABASE_KEY EMAIL PASSWORD; do
  new="MYVAULT_$v" old="TODO_$v"
  [ -n "${!new:-}" ] || { [ -n "${!old:-}" ] && export "$new=${!old}"; } \
    || { echo "Missing environment variable: $new" >&2; exit 1; }
done
[ -n "${TZ:-}" ] || { echo "Missing environment variable: TZ" >&2; exit 1; }

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
for name in myvault todo; do
  ln -sf "$PWD/cli/build/cli/linux_x64/bundle/bin/myvault" "$HOME/.local/bin/$name"
done
export PATH="$HOME/.local/bin:$PATH"

myvault server "$MYVAULT_SUPABASE_URL" "$MYVAULT_SUPABASE_KEY" >/dev/null
# `myvault login` reads the password from standard input when there is no terminal.
printf '%s\n' "$MYVAULT_PASSWORD" | myvault login --email "$MYVAULT_EMAIL"
echo "Ready. Use: $HOME/.local/bin/myvault (run 'myvault sync' after making changes)"
