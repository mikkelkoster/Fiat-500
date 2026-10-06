#!/bin/bash
# Builds the app, runs the unit tests and screenshots each screen on sample data (-preheatDemo).
# Needs a Mac with Xcode and XcodeGen (brew install xcodegen).
# Usage: scripts/build-and-capture.sh ["iPhone 16 Pro"]
set -euo pipefail
cd "$(dirname "$0")/.."

DEVICE="${1:-}"
OUT=screenshots
BUNDLE=dk.koster.FiatPreheat
DERIVED=build/DerivedData

if [ -z "$DEVICE" ]; then
  # The newest available iPhone simulator.
  DEVICE=$(xcrun simctl list devices available | grep -E '^\s+iPhone' | tail -1 | sed -E 's/^ +(.*) \([0-9A-F-]+\).*/\1/')
fi
echo "▸ Simulator: $DEVICE"

echo "▸ Generating project"
xcodegen --quiet

echo "▸ Building and running unit tests"
xcodebuild test \
  -project FiatPreheat.xcodeproj -scheme FiatPreheat \
  -destination "platform=iOS Simulator,name=$DEVICE" \
  -derivedDataPath "$DERIVED" \
  CODE_SIGNING_ALLOWED=NO \
  | tee build/xcodebuild.log | grep -E "error:|warning: .*FiatPreheat|Test Case|Executed|BUILD|TEST" || true
if ! grep -q "TEST SUCCEEDED" build/xcodebuild.log; then
  echo "✗ Build or tests failed. Full log: build/xcodebuild.log"
  exit 1
fi

echo "▸ Capturing screens"
APP=$(find "$DERIVED/Build/Products" -name "FiatPreheat.app" -path "*iphonesimulator*" | head -1)
UDID=$(xcrun simctl list devices available | grep -F "    $DEVICE (" | head -1 | sed -E 's/.*\(([0-9A-F-]+)\).*/\1/')
xcrun simctl boot "$UDID" 2>/dev/null || true
xcrun simctl bootstatus "$UDID" -b >/dev/null
xcrun simctl status_bar "$UDID" override --time "7:12" --batteryState charged --batteryLevel 100 --wifiBars 3 --cellularBars 4 || true
xcrun simctl install "$UDID" "$APP"
mkdir -p "$OUT"

for appearance in light dark; do
  xcrun simctl ui "$UDID" appearance "$appearance"
  for screen in home preheating schedule settings; do
    xcrun simctl terminate "$UDID" "$BUNDLE" 2>/dev/null || true
    xcrun simctl launch "$UDID" "$BUNDLE" -preheatDemo -demoScreen "$screen" >/dev/null
    sleep 3
    xcrun simctl io "$UDID" screenshot --type=png "$OUT/$screen-$appearance.png" >/dev/null 2>&1
    echo "  $OUT/$screen-$appearance.png"
  done
done
xcrun simctl status_bar "$UDID" clear || true
echo "✓ Built, tests passed, screenshots in $OUT/"
