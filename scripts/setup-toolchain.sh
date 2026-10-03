#!/usr/bin/env bash
# One-time setup for building the apps. Asks for your sudo password (apt) and
# shows the Android SDK licences for you to accept. Safe to run again.
set -euo pipefail

echo "== Linux desktop build tools and Java (sudo) =="
sudo apt update
sudo apt install -y clang cmake ninja-build pkg-config libgtk-3-dev openjdk-17-jdk

echo "== Flutter on PATH =="
if ! grep -q 'development/flutter/bin' "$HOME/.bashrc"; then
  echo 'export PATH="$HOME/development/flutter/bin:$HOME/Android/Sdk/platform-tools:$PATH"' >> "$HOME/.bashrc"
fi
export PATH="$HOME/development/flutter/bin:$PATH"

echo "== Android command-line tools (about 150 MB, from dl.google.com) =="
SDK="$HOME/Android/Sdk"
if [ ! -x "$SDK/cmdline-tools/latest/bin/sdkmanager" ]; then
  mkdir -p "$SDK/cmdline-tools"
  tmp="$(mktemp -d)"
  curl -fL -o "$tmp/tools.zip" https://dl.google.com/android/repository/commandlinetools-linux-15859902_latest.zip
  unzip -q "$tmp/tools.zip" -d "$tmp"
  rm -rf "$SDK/cmdline-tools/latest"
  mv "$tmp/cmdline-tools" "$SDK/cmdline-tools/latest"
  rm -rf "$tmp"
fi
"$SDK/cmdline-tools/latest/bin/sdkmanager" "platform-tools"
flutter config --android-sdk "$SDK"

echo "== Android licences: read and answer y to accept =="
flutter doctor --android-licenses

flutter doctor
echo "Done. Open a new terminal so 'flutter' and 'adb' are on your PATH."
