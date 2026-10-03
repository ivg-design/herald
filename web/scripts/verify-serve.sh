#!/bin/zsh
# Build into .next-verify and serve on 3202 (never 3102). Usage: scripts/verify-serve.sh [port]
set -e
cd "$(dirname "$0")/.."
PORT=${1:-3202}
lsof -nP -tiTCP:$PORT -sTCP:LISTEN | xargs -r kill 2>/dev/null || true
NEXT_DIST_DIR=.next-verify npm run build 2>&1 | tail -25
NEXT_DIST_DIR=.next-verify nohup npx next start -p $PORT > .next-verify/serve.log 2>&1 &
echo "serving on $PORT (pid $!)"
sleep 2; curl -s -o /dev/null -w "%{http_code}\n" http://localhost:$PORT/
