#!/usr/bin/env bash
# Builds the `myvault` CLI and installs it to ~/.local/lib/myvault, with the
# launchers `myvault` and `todo` (its older name) in ~/.local/bin.
set -euo pipefail
cd "$(dirname "$0")/../cli"
export PATH="$HOME/development/flutter/bin:$PATH"
dart build cli
rm -rf "$HOME/.local/lib/myvault" "$HOME/.local/lib/todo"
mkdir -p "$HOME/.local/lib" "$HOME/.local/bin"
cp -r build/cli/linux_x64/bundle "$HOME/.local/lib/myvault"
for name in myvault todo; do
  printf '#!/bin/sh\nexec "$HOME/.local/lib/myvault/bin/myvault" "$@"\n' > "$HOME/.local/bin/$name"
  chmod +x "$HOME/.local/bin/$name"
done
echo "Installed: $HOME/.local/bin/myvault (and todo, its older name)"
