#!/bin/bash
# Render the real Windbar UI with fixture devices, then frame it for the App Store.
#
# The harness runs inside the sandboxed host app, so it can only write to its own
# temp directory. This copies the results out and hands them to the compositor.
set -eo pipefail
cd "$(dirname "$0")/.."

RAW="$PWD/design/screenshots/raw"
mkdir -p "$RAW"

echo "==> rendering UI with fixture devices"
LOG=$(mktemp)
# The compilation conditions are pinned rather than inherited. These renders
# become the App Store listing, and the Debug configuration sets
# WINDBAR_DONATIONS so the donation UI can be worked on locally. Inheriting it
# would put a "Support Windbar" row and a donations debug panel into the
# screenshots uploaded to Apple, and guideline 3.1.1 covers metadata as
# squarely as it covers the binary. Nothing downstream would catch it: the
# fastlane guard only ever greps the binary.
TEST_RUNNER_WINDBAR_SHOT_DIR=1 xcodebuild test \
  -project Windbar.xcodeproj -scheme Windbar -destination 'platform=macOS' \
  -only-testing:WindbarTests/ScreenshotHarness \
  SWIFT_ACTIVE_COMPILATION_CONDITIONS=DEBUG \
  CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM="" \
  PROVISIONING_PROFILE_SPECIFIER="" > "$LOG" 2>&1 || { tail -30 "$LOG"; exit 1; }

grep -o '/[^ ]*windbar-screenshots/[0-9]*\.png' "$LOG" | sort -u | while read -r f; do
  [ -f "$f" ] && cp "$f" "$RAW/$(basename "$f")" && echo "    $(basename "$f")"
done
rm -f "$LOG"

COUNT=$(ls "$RAW"/*.png 2>/dev/null | wc -l | tr -d ' ')
[ "$COUNT" = "0" ] && { echo "No screenshots rendered."; exit 1; }
echo "==> $COUNT raw capture(s) in design/screenshots/raw"

echo "==> compositing store frames"
python3 design/make_screenshots.py
