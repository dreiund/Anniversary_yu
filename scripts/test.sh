#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
SIM=$(xcrun simctl list devices available | grep -E '^[[:space:]]+iPhone' | head -1 | sed -E 's/^ +//; s/ \(.*$//')
[ -n "$SIM" ] || { echo "未找到可用 iPhone 模拟器"; exit 1; }
echo "▶ 模拟器: $SIM"
xcodebuild test \
  -project Anniversary.xcodeproj -scheme Anniversary \
  -destination "platform=iOS Simulator,name=$SIM" \
  -skip-testing:AnniversaryUITests \
  -derivedDataPath .build -quiet
echo "✅ 测试通过"
