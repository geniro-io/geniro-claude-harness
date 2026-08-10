#!/usr/bin/env bash
# Suite for hooks/block-bulk-tag-push.sh — deny path, allow paths, the
# allowlist bypass, and the fail-closed paths. Both directions on the matcher:
# a form that must block and a near-miss that must not.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
FAILED=0
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
echo '{"allow_patterns": []}' > "$TMP/safety.json"
echo '{"allow_patterns": ["bulk-tag-push"]}' > "$TMP/bypass.json"

run() { echo "{\"tool_input\":{\"command\":\"$1\"}}" | SAFETY_JSON="$2" bash "$ROOT/hooks/block-bulk-tag-push.sh" >/dev/null 2>&1; echo $?; }

check() { [ "$2" = "$3" ] || { echo "FAIL: $1 (want $3, got $2)"; FAILED=1; }; }

check "single tag push allowed"        "$(run 'git push origin v2.4' "$TMP/safety.json")"          0
check "bulk tag push blocked"          "$(run 'git push --tags origin' "$TMP/safety.json")"        2
check "global -C form blocked"         "$(run 'git -C /repo push --tags' "$TMP/safety.json")"      2
check "global -c form blocked"         "$(run 'git -c a=b push --tags' "$TMP/safety.json")"        2
check "--follow-tags not blocked"      "$(run 'git push --follow-tags' "$TMP/safety.json")"        0
check "allowlist bypass permits"       "$(run 'git push --tags origin' "$TMP/bypass.json")"        0
check "fail closed, missing allowlist" "$(run 'git push --tags origin' "$TMP/absent.json")"        2

# Malformed stdin must land on the deny code, not on whatever jq exits with.
echo 'not json' | SAFETY_JSON="$TMP/safety.json" bash "$ROOT/hooks/block-bulk-tag-push.sh" >/dev/null 2>&1
check "fail closed, unparseable stdin" "$?" 2

echo "block-bulk-tag-push: done"
[ "$FAILED" -eq 0 ]
