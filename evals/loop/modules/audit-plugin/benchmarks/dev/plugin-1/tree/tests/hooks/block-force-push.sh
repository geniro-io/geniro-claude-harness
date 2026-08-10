#!/usr/bin/env bash
# Suite for hooks/block-force-push.sh
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
FAILED=0

run() { echo "{\"tool_input\":{\"command\":\"$1\"}}" | bash "$ROOT/hooks/block-force-push.sh" >/dev/null 2>&1; echo $?; }

[ "$(run 'git push --force origin main')" = "2" ] || { echo "FAIL: force push not blocked"; FAILED=1; }
[ "$(run 'git push origin main')" = "0" ] || { echo "FAIL: plain push blocked"; FAILED=1; }

echo "block-force-push: done"
[ "$FAILED" -eq 0 ]
