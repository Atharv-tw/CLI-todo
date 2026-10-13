#!/usr/bin/env bash
# Redraws the website's pictures in site/img from made-up data (never your
# own): see apps/app/tool/screenshots_test.dart.
set -euo pipefail
cd "$(dirname "$0")/../apps/app"
export PATH="$HOME/development/flutter/bin:$PATH"
# The pictures show a day half done, so the app is told it is 14:00 by
# picking the timezone where that is true right now.
hour=$((10#$(date -u +%H)))
shift=$((hour - 14))
if [ "$shift" -ge 0 ]; then zone="Etc/GMT+$shift"; else zone="Etc/GMT$shift"; fi
TZ="$zone" flutter test tool/screenshots_test.dart
ls -la ../../site/img
