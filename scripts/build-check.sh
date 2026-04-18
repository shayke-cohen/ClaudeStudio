#!/bin/bash
# Fast Xcode build check — compile only, no tests (~15-20s).
# Usage: bash scripts/build-check.sh
set -euo pipefail
cd "$(dirname "$0")/.."

echo "→ Building Odyssey..."
if OUTPUT=$(xcodebuild build \
  -project Odyssey.xcodeproj \
  -scheme Odyssey \
  -destination 'platform=macOS' \
  -quiet 2>&1); then
  echo "✓ Build succeeded"
else
  echo "✗ Build failed"
  echo "$OUTPUT" | tail -30
  exit 1
fi
