#!/bin/zsh
set -euo pipefail
cd ~/github/herald
VER=$1; BUILD=$2
ok=0; for i in 1 2; do if swift test 2>&1 | grep -E 'Executed [0-9]+ tests' | tail -1 | grep -q ' 0 failures'; then ok=1; break; fi; echo "test run $i had a failure, retrying"; done
[ $ok = 1 ] || { echo "tests failing twice, abort"; exit 1; }
xcodegen generate >/dev/null
mac-notarize --dmg 2>&1 | tail -1
APP=/Users/ivg/Library/Developer/Xcode/DerivedData/Herald-epyzrtfbiibpkzdkavzgarxyuofu/Build/Products/Release/Herald.app
[ -d "$APP" ] || { echo "no app"; exit 1; }
V=$(defaults read "$APP/Contents/Info.plist" CFBundleShortVersionString); [ "$V" = "$VER" ] || { echo "built $V, expected $VER"; exit 1; }
osascript -e 'tell application "Herald" to quit' >/dev/null 2>&1 || true; sleep 2; pkill -x Herald || true; sleep 1
rm -rf /Applications/Herald.app && ditto "$APP" /Applications/Herald.app && open -g /Applications/Herald.app && sleep 4
pgrep -x Herald >/dev/null && echo "running $(defaults read /Applications/Herald.app/Contents/Info.plist CFBundleShortVersionString) b$(defaults read /Applications/Herald.app/Contents/Info.plist CFBundleVersion)"
git add -A; git diff --cached --quiet || git commit -q -m "Release $VER (Build $BUILD): see CHANGELOG.md"
git tag -a "v$VER" -m "Herald $VER (Build $BUILD)" && git push -q origin main "v$VER"
[ "$(git rev-parse "v$VER^{commit}")" = "$(git rev-parse HEAD)" ] || { echo "tag is not at HEAD"; exit 1; }
gh release create "v$VER" "release/Herald-$VER-build$BUILD-macOS.dmg" "release/Herald-$VER-build$BUILD-macOS.dmg.sha256" --repo ivg-design/herald --title "Herald $VER (Build $BUILD)" --notes-file <(awk -v v="$VER" '$0 ~ "^## "v{p=1;print;next} /^## /{if(p)exit} p' CHANGELOG.md) 2>&1 | tail -1
