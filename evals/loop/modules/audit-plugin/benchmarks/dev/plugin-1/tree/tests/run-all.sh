#!/usr/bin/env bash
# Run every tests/**/*.sh suite.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
FAILED=0
for suite in "$ROOT"/tests/*/*.sh; do
  bash "$suite" || FAILED=1
done
[ "$FAILED" -eq 0 ]
