#!/usr/bin/env bash
# Suite for lib/paths.sh
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
source "$ROOT/lib/paths.sh"
FAILED=0

is_inside /w/a /w || { echo "FAIL: /w/a not inside /w"; FAILED=1; }
is_inside /x/a /w && { echo "FAIL: /x/a counted as inside /w"; FAILED=1; }

echo "paths: done"
[ "$FAILED" -eq 0 ]
