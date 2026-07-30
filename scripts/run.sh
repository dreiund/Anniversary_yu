#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
./scripts/build.sh
SIM=$(xcrun simctl list devices available | grep -E '^[[:space:]]+iPhone' | head -1 | sed -E 's/^ +//; s/ \(.*$//')
xcrun simctl boot "$SIM" 2>/dev/null || true
open -a Simulator
xcrun simctl install booted ".build/Build/Products/Debug-iphonesimulator/Anniversary.app"
xcrun simctl launch booted com.fkc.anniversary
