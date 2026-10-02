#!/bin/bash
# Bundles the Cloudflare Worker (relay/src) into Resources/relay/worker.js, the single ES module Herald uploads through the
# Cloudflare API when the user presses "Deploy" (no wrangler, no Node on the user's Mac). Records the source hash in bundle.json;
# Tests/HeraldTests/RelayBundleTests fails when relay/ changed and this was not re-run (`make relay-bundle`).
set -euo pipefail
cd "$(dirname "$0")/.."
OUT=Resources/relay
mkdir -p "$OUT"

# The hash: sha256 of the sorted "<sha256>  <path>" listing of the sources that make the bundle.
source_hash() {
  ( cd relay && for f in $(ls src/*.ts | LC_ALL=C sort) wrangler.toml; do shasum -a 256 "$f"; done ) | shasum -a 256 | cut -d' ' -f1
}
HASH=$(source_hash)

( cd relay && [ -d node_modules ] || npm install --no-audit --no-fund >/dev/null )
TMP=$(mktemp -d)
( cd relay && npx wrangler deploy --dry-run --outdir "$TMP" >/dev/null 2>&1 )
[ -f "$TMP/index.js" ] || { echo "wrangler produced no index.js" >&2; exit 1; }
cp "$TMP/index.js" "$OUT/worker.js"
rm -rf "$TMP"
COMPAT=$(sed -n 's/^compatibility_date *= *"\(.*\)"/\1/p' relay/wrangler.toml | head -1)
BYTES=$(wc -c < "$OUT/worker.js" | tr -d ' ')
printf '{\n  "sourceHash": "%s",\n  "mainModule": "worker.js",\n  "compatibilityDate": "%s",\n  "bytes": %s\n}\n' "$HASH" "$COMPAT" "$BYTES" > "$OUT/bundle.json"
echo "relay bundle: $OUT/worker.js ($BYTES bytes), source hash $HASH"
