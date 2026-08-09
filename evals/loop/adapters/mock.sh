#!/usr/bin/env bash
# Test adapter: deterministic canned result, no network, no cost.
# Used by tests/evals/loop-core.sh to exercise the driver end-to-end.
# Override the emitted review text via LOOP_MOCK_RESULT.
set -euo pipefail
MODEL="$1"; WORKSPACE="$2"; PROMPT="$3"; OUT="$4"; ERR="$5"
: "$MODEL" "$WORKSPACE"; : > "$ERR"
RESULT="${LOOP_MOCK_RESULT:-### [HIGH] Mock finding
**File:** src/mock.ts:1
**Confidence:** 90
mock body

## Dimension Summary
mock}"
head -c 1 "$PROMPT" >/dev/null
jq -n --arg r "$RESULT" \
  '{type:"result", result:$r, is_error:false, usage:{inputTokens:100, cacheReadTokens:0, outputTokens:50}}' > "$OUT"
