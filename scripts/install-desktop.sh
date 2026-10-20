#!/usr/bin/env bash
# Builds the Linux desktop app and installs it to ~/.local/lib/vault-app with a launcher entry.
set -euo pipefail
cd "$(dirname "$0")/../apps/app"
export PATH="$HOME/development/flutter/bin:$PATH"
CONFIG=../../config.local.json
flutter build linux --release ${CONFIG:+$([ -f "$CONFIG" ] && echo --dart-define-from-file="$CONFIG")}
rm -rf "$HOME/.local/lib/vault-app" "$HOME/.local/lib/todo-app" "$HOME/.local/share/applications/dev.atharv.todo_app.desktop"
ICONS="$HOME/.local/share/icons/hicolor/scalable/apps"
mkdir -p "$HOME/.local/lib" "$HOME/.local/share/applications" "$ICONS"
cp ../../assets/logo.svg "$ICONS/dev.atharv.vault.svg"
cp -r build/linux/x64/release/bundle "$HOME/.local/lib/vault-app"
cat > "$HOME/.local/share/applications/dev.atharv.vault.desktop" <<DESKTOP
[Desktop Entry]
Type=Application
Name=Vault
Comment=Your second brain: goals, days, diary and memory
Exec=$HOME/.local/lib/vault-app/vault
Icon=dev.atharv.vault
Categories=Utility;Office;
StartupWMClass=dev.atharv.vault
DESKTOP
echo "Installed: Vault (in the app grid)"
