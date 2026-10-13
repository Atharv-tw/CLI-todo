#!/usr/bin/env bash
# Builds the Android app and installs it on the phone connected over USB.
set -euo pipefail
cd "$(dirname "$0")/../apps/app"
export PATH="$HOME/development/flutter/bin:$HOME/Android/Sdk/platform-tools:$PATH"
CONFIG=../../config.local.json
# One APK per processor type: the speech library is large, and a phone only
# needs its own.
flutter build apk --release --split-per-abi $([ -f "$CONFIG" ] && echo --dart-define-from-file="$CONFIG")
ABI="$(adb shell getprop ro.product.cpu.abi | tr -d '\r')"
adb install -r "build/app/outputs/flutter-apk/app-$ABI-release.apk"
