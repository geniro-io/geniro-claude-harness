#!/usr/bin/env bash
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
FAILED=0

run() { printf '%s' "$1" | bash "$ROOT/hooks/block-secret-write.sh" >/dev/null 2>&1; echo $?; }

[ "$(run '{"tool_input":{"content":"api_key: abc123"}}')" = "2" ] || { echo "FAIL: secret not blocked"; FAILED=1; }
[ "$(run '{"tool_input":{"content":"port: 8080"}}')" = "0" ] || { echo "FAIL: clean write blocked"; FAILED=1; }

echo "block-secret-write: done"
[ "$FAILED" -eq 0 ]
