#!/bin/bash
# Build the herald CLI (release) and install it to /usr/local/bin, or ~/bin if that is not writable.
set -euo pipefail
cd "$(dirname "$0")/.."
swift build -c release --product herald
BIN="$(swift build -c release --show-bin-path)/herald"
DEST=/usr/local/bin
if [ ! -d "$DEST" ] || [ ! -w "$DEST" ]; then
  DEST="$HOME/bin"
  mkdir -p "$DEST"
fi
install -m 755 "$BIN" "$DEST/herald"
echo "Installed herald to $DEST/herald"
case ":$PATH:" in *":$DEST:"*) ;; *) echo "Note: $DEST is not on your PATH." ;; esac
