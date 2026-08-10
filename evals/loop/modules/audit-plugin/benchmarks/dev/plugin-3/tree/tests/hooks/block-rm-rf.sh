#!/usr/bin/env bash
# Suite for hooks/block-rm-rf.sh
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
FAILED=0
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
echo '{"allow_patterns": []}' > "$TMP/safety.json"

run() { echo "{\"tool_input\":{\"command\":\"$1\"}}" | SAFETY_JSON="$TMP/safety.json" bash "$ROOT/hooks/block-rm-rf.sh" >/dev/null 2>&1; echo $?; }

[ "$(run 'ls -la')" = "0" ] || { echo "FAIL: plain command blocked"; FAILED=1; }
[ "$(run 'git status')" = "0" ] || { echo "FAIL: git status blocked"; FAILED=1; }

echo "block-rm-rf: done"
[ "$FAILED" -eq 0 ]
