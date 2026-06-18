#!/usr/bin/env bash
# Numeric smoke test for lib/score-formula.sh — the L2 ranking weights shared by
# query-learnings (--score-min) and archive-stale. The two callers MUST score
# identically: the archiver reaps an entry only when its score falls below the
# floor, so a silent coefficient change here would make it deprecate entries the
# ranker would still surface. The formula was referenced only in test comments;
# this exercises each weight function numerically so a drift fails the suite.
#
# Run: bash tests/memory/score-formula.sh

set -uo pipefail
REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"

TESTS_RUN=0
TESTS_FAILED=0
pass() { TESTS_RUN=$((TESTS_RUN + 1)); echo "PASS: $1"; }
fail() { TESTS_RUN=$((TESTS_RUN + 1)); TESTS_FAILED=$((TESTS_FAILED + 1)); echo "FAIL: $1" >&2; }

# shellcheck disable=SC1091
source "$REPO_ROOT/lib/score-formula.sh"

# Evaluate a jq expression with the shared defs prepended.
jqf() { jq -n "$GENIRO_SCORE_JQ_DEFS $1"; }

# approx <got> <want> [tol] — float compare with a tolerance (jq emits floats).
approx() { awk -v a="$1" -v b="$2" -v t="${3:-0.001}" 'BEGIN{d=a-b; if(d<0)d=-d; exit !(d<=t)}'; }

chk() { # chk <expr> <want> <label> [tol]
  local got; got="$(jqf "$1")"
  if approx "$got" "$2" "${4:-0.001}"; then pass "$3 (=$got)"; else fail "$3 — got $got want $2"; fi
}

# trust_weight: verified=1.0, retrieved=0.66, anything else=0.33
chk '("verified"  | trust_weight)' 1.0  "trust_weight verified = 1.0"
chk '("retrieved" | trust_weight)' 0.66 "trust_weight retrieved = 0.66"
chk '("inferred"  | trust_weight)' 0.33 "trust_weight other = 0.33"

# recency_decay(age; tau): null age -> 0.5; age 0 -> 1; age==tau -> e^-1
chk 'recency_decay(null; 90)' 0.5      "recency_decay(null) = 0.5"
chk 'recency_decay(0; 90)'    1.0      "recency_decay(age 0) = 1.0"
chk 'recency_decay(90; 90)'   0.367879 "recency_decay(age==tau) = e^-1" 0.0001

# access_weight(n) = 1 + log10(n+1): n=0 -> 1.0, n=9 -> 2.0
chk 'access_weight(0)' 1.0 "access_weight(0) = 1.0"
chk 'access_weight(9)' 2.0 "access_weight(9) = 2.0"

# recurrence_weight(n) = 1 + ln(max(n,1)): n=1 (and clamped n=0) -> 1.0; n=20 -> ~4.0
chk 'recurrence_weight(1)'  1.0    "recurrence_weight(1) = 1.0"
chk 'recurrence_weight(0)'  1.0    "recurrence_weight(0) clamps to 1.0"
chk 'recurrence_weight(20)' 3.9957 "recurrence_weight(20) ~ 4.0" 0.001

echo
echo "Tests run:    $TESTS_RUN"
echo "Tests failed: $TESTS_FAILED"
[ "$TESTS_FAILED" -eq 0 ]
