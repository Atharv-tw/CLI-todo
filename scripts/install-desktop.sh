#!/usr/bin/env bash
# Builds the Linux desktop app and installs it to ~/.local/lib/todo-app with a launcher entry.
set -euo pipefail
cd "$(dirname "$0")/../apps/app"
export PATH="$HOME/development/flutter/bin:$PATH"
CONFIG=../../config.local.json
flutter build linux --release ${CONFIG:+$([ -f "$CONFIG" ] && echo --dart-define-from-file="$CONFIG")}
rm -rf "$HOME/.local/lib/todo-app"
ICONS="$HOME/.local/share/icons/hicolor/scalable/apps"
mkdir -p "$HOME/.local/lib" "$HOME/.local/share/applications" "$ICONS"
cp ../../assets/logo.svg "$ICONS/dev.atharv.todo_app.svg"
cp -r build/linux/x64/release/bundle "$HOME/.local/lib/todo-app"
cat > "$HOME/.local/share/applications/dev.atharv.todo_app.desktop" <<DESKTOP
[Desktop Entry]
Type=Application
Name=Todo
Comment=Tasks, habits and focus sessions
Exec=$HOME/.local/lib/todo-app/todo_app
Icon=dev.atharv.todo_app
Categories=Utility;Office;
StartupWMClass=dev.atharv.todo_app
DESKTOP
echo "Installed: Todo (in the app grid)"
