#!/usr/bin/env bash
# Builds the `todo` CLI and installs it to ~/.local/lib/todo with a launcher in ~/.local/bin.
set -euo pipefail
cd "$(dirname "$0")/../cli"
export PATH="$HOME/development/flutter/bin:$PATH"
dart build cli
rm -rf "$HOME/.local/lib/todo"
mkdir -p "$HOME/.local/lib" "$HOME/.local/bin"
cp -r build/cli/linux_x64/bundle "$HOME/.local/lib/todo"
printf '#!/bin/sh\nexec "$HOME/.local/lib/todo/bin/todo" "$@"\n' > "$HOME/.local/bin/todo"
chmod +x "$HOME/.local/bin/todo"
echo "Installed: $HOME/.local/bin/todo"
