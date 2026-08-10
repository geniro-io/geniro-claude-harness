#!/usr/bin/env bash
# Suite for hooks/block-bulk-tag-push.sh — allow path, deny path, fail-closed path.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
FAILED=0
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
echo '{"allow_patterns": []}' > "$TMP/safety.json"

run() { echo "{\"tool_input\":{\"command\":\"$1\"}}" | SAFETY_JSON="$2" bash "$ROOT/hooks/block-bulk-tag-push.sh" >/dev/null 2>&1; echo $?; }

[ "$(run 'git push origin v2.4' "$TMP/safety.json")" = "0" ] || { echo "FAIL: single tag push blocked"; FAILED=1; }
[ "$(run 'git push --tags origin' "$TMP/safety.json")" = "2" ] || { echo "FAIL: bulk tag push not blocked"; FAILED=1; }
[ "$(run 'git push --tags origin' "$TMP/absent.json")" = "2" ] || { echo "FAIL: did not fail closed on a missing allowlist"; FAILED=1; }

echo "block-bulk-tag-push: done"
[ "$FAILED" -eq 0 ]
