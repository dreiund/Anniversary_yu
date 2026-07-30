#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
command -v xcodegen >/dev/null || { echo "缺少 xcodegen: brew install xcodegen"; exit 1; }
xcodegen generate
