#!/usr/bin/env bash
# Suite for lib/config.sh
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
source "$ROOT/lib/config.sh"
FAILED=0

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

echo '{"retries": 5}' > "$TMP/s.json"
[ "$(retry_limit "$TMP/s.json")" = "5" ] || { echo "FAIL: retry_limit"; FAILED=1; }

echo "config: done"
[ "$FAILED" -eq 0 ]
