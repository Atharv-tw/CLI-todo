#!/usr/bin/env bash
# Builds the Android app and installs it on the phone connected over USB.
set -euo pipefail
cd "$(dirname "$0")/../apps/app"
export PATH="$HOME/development/flutter/bin:$HOME/Android/Sdk/platform-tools:$PATH"
CONFIG=../../config.local.json
flutter build apk --release $([ -f "$CONFIG" ] && echo --dart-define-from-file="$CONFIG")
adb install -r build/app/outputs/flutter-apk/app-release.apk
