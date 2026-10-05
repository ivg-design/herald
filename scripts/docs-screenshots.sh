#!/bin/zsh
# Re-takes the documentation screenshots of Herald with no window ever shown on a display and nothing activated.
#
#   scripts/docs-screenshots.sh [derivedDataDir]            # all shots
#   HERALD_SCREENSHOTS_ONLY=banner-,history scripts/docs-screenshots.sh   # a subset (names or prefixes, comma separated)
#
# 1. builds the Debug app into <derivedDataDir> (default $TMPDIR/herald-docs-shots-dd),
# 2. runs its hidden screenshot mode (HERALD_SCREENSHOTS=<raw dir>; see Sources/Herald/Debug/ScreenshotMode.swift for the switches),
#    which captures raw offscreen window images plus shots-meta.json and prints its log,
# 3. composites them on gradients into web/public/shots/docs (<name>.png 1x, <name>@2x.png) and writes manifest.json there.
# Env: HERALD_SCREENSHOTS_ONLY (subset), HERALD_SHOTS_RAW (raw dir, default $TMPDIR/herald-docs-shots-raw), HERALD_SHOTS_TIMEOUT (seconds, default 300).
set -e
cd "$(dirname "$0")/.."
ROOT=$PWD
DD=${1:-${TMPDIR:-/tmp}/herald-docs-shots-dd}
RAW=${HERALD_SHOTS_RAW:-${TMPDIR:-/tmp}/herald-docs-shots-raw}
LIMIT=${HERALD_SHOTS_TIMEOUT:-300}
[ -z "$HERALD_SCREENSHOTS_ONLY" ] && rm -rf "$RAW"
mkdir -p "$RAW"

command -v xcodegen >/dev/null && xcodegen generate >/dev/null
xcodebuild -project Herald.xcodeproj -scheme Herald -configuration Debug -derivedDataPath "$DD" build | tail -3

LOG="$RAW/capture.log"
: > "$LOG"
BIN="$DD/Build/Products/Debug/Herald.app/Contents/MacOS/Herald"
# One launch per group of shots (a long single run can trip an AppKit layout crash in the offscreen windows); a subset asks for one launch.
if [ -n "$HERALD_SCREENSHOTS_ONLY" ]; then SETS=("$HERALD_SCREENSHOTS_ONLY"); else SETS=("designer-" "settings-" "menu" "banner-" "history,template-editor"); fi
for G in "${SETS[@]}"; do
  HERALD_SCREENSHOTS_ONLY="$G" HERALD_SCREENSHOTS="$RAW" "$BIN" >> "$LOG" 2>&1 &
  PID=$!
  for ((i = 0; i < LIMIT; i++)); do kill -0 $PID 2>/dev/null || break; sleep 1; done
  if kill -0 $PID 2>/dev/null; then echo "timed out after ${LIMIT}s, stopping pid $PID"; kill $PID; fi
  wait $PID 2>/dev/null || echo "run '$G' ended abnormally (see $LOG)"
done
grep "^screenshots:" "$LOG"

(cd web && node scripts/frame-shots.mjs "$RAW" --docs --out public/shots/docs)
echo "wrote $ROOT/web/public/shots/docs ($(du -sh web/public/shots/docs | cut -f1))"
