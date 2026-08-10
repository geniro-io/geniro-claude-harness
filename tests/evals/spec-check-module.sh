#!/usr/bin/env bash
# Suite for the evals/loop spec-check module: stage-task.sh "spec" mode and the
# loop_lib.py "spec-claims" parser.
#
# Run: bash tests/evals/spec-check-module.sh
#
# Both directions on every assertion: a shape that must parse and one that must
# not, so a parser silently reduced to "emit nothing" is visible here rather
# than as a zero-recall sweep nobody can explain.
#
# Plugin-developer tooling only — not shipped to user projects.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
LOOP="$REPO_ROOT/evals/loop"
MODULE="$LOOP/modules/spec-check"

SANDBOX="$(mktemp -d)"
trap 'rm -rf "$SANDBOX"' EXIT

TESTS_RUN=0
TESTS_FAILED=0
pass() { TESTS_RUN=$((TESTS_RUN + 1)); echo "PASS: $1"; }
fail() { TESTS_RUN=$((TESTS_RUN + 1)); TESTS_FAILED=$((TESTS_FAILED + 1)); echo "FAIL: $1" >&2; }

# --- module declaration -----------------------------------------------------

if jq -e '.parser == "spec-claims" and .pass_expr != null and .negative_pass_expr != null' \
     "$MODULE/target.json" >/dev/null 2>&1; then
  pass "target.json names the spec-claims parser and both pass expressions"
else
  fail "target.json is missing the parser or a pass expression"
fi

if [ -f "$MODULE/variants/champion/preamble.md" ]; then
  pass "champion carries a preamble"
else
  fail "champion has no preamble.md"
fi

# --- stage-task.sh "spec" mode ----------------------------------------------

TASK="$MODULE/benchmarks/dev/planted-1"
STAGE="$SANDBOX/stage"
if bash "$LOOP/stage-task.sh" "$TASK" "$STAGE" >/dev/null 2>&1; then
  pass "spec mode stages without error"
else
  fail "stage-task.sh failed on a spec-mode task"
fi

if [ -f "$STAGE/spec.md" ]; then pass "spec mode materializes spec.md"
else fail "spec mode did not write spec.md"; fi
if [ -d "$STAGE/tree" ] && [ -n "$(ls -A "$STAGE/tree" 2>/dev/null)" ]; then
  pass "spec mode materializes a non-empty tree"
else fail "spec mode left the tree empty"; fi
if [ ! -f "$STAGE/diff.patch" ]; then pass "spec mode writes no diff — nothing changed"
else fail "spec mode wrote a diff.patch"; fi

# A task whose .spec does not resolve must fail loudly, not stage a specless run.
BADTASK="$SANDBOX/badtask"
mkdir -p "$BADTASK/tree"
cat > "$BADTASK/task.json" <<'JSON'
{"id":"bad","mode":"spec","tree_dir":"tree","spec":"absent.md"}
JSON
if bash "$LOOP/stage-task.sh" "$BADTASK" "$SANDBOX/stage-bad" >/dev/null 2>&1; then
  fail "a missing spec staged silently"
else
  pass "a missing spec fails staging instead of running specless"
fi

# --- the spec-claims parser -------------------------------------------------

mk_raw() {  # mk_raw <out-path> <result-text>
  python3 - "$1" "$2" <<'PY'
import json, sys
json.dump({"type": "result", "result": sys.argv[2], "is_error": False,
           "usage": {"inputTokens": 10, "cacheReadTokens": 0, "outputTokens": 5}},
          open(sys.argv[1], "w"))
PY
}
parse() { python3 "$LOOP/loop_lib.py" parse --parser spec-claims "$1"; }

mk_raw "$SANDBOX/raw-claims.json" '### [REFUTED] the job runs every minute
**Cited:** src/jobs/cron.ts:12
**Evidence:** "schedule: \"0 */6 * * *\""
**Why:** six-hourly, not per-minute.

### [CLARIFIED] no cache exists
**Cited:** src/cache/index.ts:4
**Evidence:** "export const cache = new LRU(500)"
**Why:** one exists, but only on the read path.

## Claim Summary
Checked 5 claims: 3 confirmed, 1 clarified, 1 refuted.'
OUT="$(parse "$SANDBOX/raw-claims.json")"

n="$(printf '%s' "$OUT" | python3 -c 'import json,sys; print(len(json.load(sys.stdin)))')"
if [ "$n" = "2" ]; then pass "one finding per flagged claim, none for confirmed ones"
else fail "expected 2 findings, got $n"; fi

sev="$(printf '%s' "$OUT" | python3 -c 'import json,sys; f=json.load(sys.stdin); print(f[0]["severity"], f[1]["severity"])')"
if [ "$sev" = "HIGH MEDIUM" ]; then pass "REFUTED outranks CLARIFIED on the severity scale"
else fail "severity mapping drifted: $sev"; fi

fileref="$(printf '%s' "$OUT" | python3 -c 'import json,sys; f=json.load(sys.stdin); print(f[0]["file"], f[0]["line_start"])')"
if [ "$fileref" = "src/jobs/cron.ts 12" ]; then pass "Cited: resolves to file + line"
else fail "Cited: parse drifted: $fileref"; fi

ev="$(printf '%s' "$OUT" | python3 -c 'import json,sys; print(all(x["has_evidence"] for x in json.load(sys.stdin)))')"
if [ "$ev" = "True" ]; then pass "an Evidence line sets has_evidence"
else fail "has_evidence not set from the Evidence line"; fi

# A clean pass — summary only, no blocks — must parse to zero findings, not to junk.
mk_raw "$SANDBOX/raw-clean.json" '## Claim Summary
Checked 4 claims: 4 confirmed, 0 clarified, 0 refuted.'
n="$(parse "$SANDBOX/raw-clean.json" | python3 -c 'import json,sys; print(len(json.load(sys.stdin)))')"
if [ "$n" = "0" ]; then pass "a clean pass parses to zero findings"
else fail "clean pass produced $n findings"; fi

# The review parser must not pick these up, and vice versa — a module reading the
# wrong parser should score zero rather than silently half-match.
n="$(python3 "$LOOP/loop_lib.py" parse "$SANDBOX/raw-claims.json" | python3 -c 'import json,sys; print(len(json.load(sys.stdin)))')"
if [ "$n" = "0" ]; then pass "the review parser ignores claim verdicts (no cross-talk)"
else fail "review parser matched $n claim blocks"; fi

# --- the planted task's rubric ----------------------------------------------

if jq -e '.version and (.items | length) > 0 and all(.items[]; .id and .description and .must_find != null)' \
     "$TASK/rubric.json" >/dev/null 2>&1; then
  pass "planted-1 rubric carries a version and complete items"
else
  fail "planted-1 rubric is malformed"
fi

echo
echo "spec-check-module: $TESTS_RUN run, $TESTS_FAILED failed"
[ "$TESTS_FAILED" -eq 0 ]
