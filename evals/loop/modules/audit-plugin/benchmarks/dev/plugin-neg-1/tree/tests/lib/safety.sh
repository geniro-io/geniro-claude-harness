#!/usr/bin/env bash
# Suite for lib/safety.sh — both directions on every branch.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
source "$ROOT/lib/safety.sh"
FAILED=0
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

echo '{"allow_patterns": ["bulk-tag-push"]}' > "$TMP/ok.json"
[ "$(SAFETY_JSON="$TMP/ok.json" read_allow_patterns)" = "bulk-tag-push " ] || { echo "FAIL: patterns not read"; FAILED=1; }

SAFETY_JSON="$TMP/absent.json" read_allow_patterns >/dev/null 2>&1 && { echo "FAIL: missing file returned success"; FAILED=1; }

echo 'not json' > "$TMP/bad.json"
SAFETY_JSON="$TMP/bad.json" read_allow_patterns >/dev/null 2>&1 && { echo "FAIL: invalid JSON returned success"; FAILED=1; }

echo "safety: done"
[ "$FAILED" -eq 0 ]
