#!/usr/bin/env bash
# Contract tests for the debug module's additions to evals/loop.
#
# Run: bash tests/evals/debug-module.sh   (auto-discovered by tests/run-all.sh)
# Exits non-zero on any failure. No network, no paid calls.
#
# Contracts under test:
#   1. `debug-hypotheses` parses the shipped `## Hypotheses` block shape — one
#      finding per `### H<N>` block, mechanism in the title, and both `H1:` and
#      `H2.` heading punctuations accepted.
#   2. The `Targeted:` line carries the location, NOT the heading — two
#      hypotheses naming one module for different mechanisms stay distinct, and
#      a path mentioned only in the mechanism text is not harvested as the site.
#   3. A block whose `Status:` is not `pending` is still emitted. The preamble
#      forbids testing, so a run that reports `confirmed` has violated it; the
#      violation belongs on the noise axis, not silently dropped by the parser.
#   4. Per-module `judge_framing` replaces the defect-grading wording, so a
#      hypothesis set is graded as candidate causes rather than as defects.
#   5. `noise_floor: null` makes compare.sh refuse to read the noise axis — the
#      mechanical half of "a module that has not run its A-vs-A cannot screen".
#   6. Every `champion_sync` section named in target.json still resolves to a
#      real heading. Extraction hard-fails on a renamed heading upstream, and a
#      silently empty criteria file would read downstream as a pass that had
#      nothing to go on.
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
LOOP="$REPO_ROOT/evals/loop"
TMP="$(cd "$(mktemp -d)" && pwd -P)"
trap 'rm -rf "$TMP"' EXIT

TESTS_RUN=0
TESTS_FAILED=0
pass() { TESTS_RUN=$((TESTS_RUN + 1)); echo "PASS: $1"; }
fail() { TESTS_RUN=$((TESTS_RUN + 1)); TESTS_FAILED=$((TESTS_FAILED + 1)); echo "FAIL: $1" >&2; }

# ---- 1 + 2 + 3. debug-hypotheses parser ----
cat > "$TMP/hyp.txt" <<'EOF'
## Hypotheses

### H1: cacheKey omits the tenant id, so a role change leaves a stale profile cached
- **Targeted:** `src/cache/user.ts:42-48`
- **Mechanism:** the key is built from userId alone, so src/cache/redis.ts never sees a distinct key
- **Evidence For:** `src/cache/user.ts:44` builds the key without tenantId
- **Evidence Against:** none found
- **Test Plan:** if the key is the cause, then adding tenantId changes the cache-hit signature
- **Status:** pending

### H2. the TTL outlives the session, so entries survive invalidation
- **Targeted:** `src/cache/redis.ts:12`
- **Mechanism:** TTL is 24h against a 1h session
- **Evidence For:** `src/cache/redis.ts:12` sets EX 86400
- **Status:** confirmed

### H3: connection pool exhausted under load
- **Targeted:** `deploy/values.yaml:31`
- **Mechanism:** maxConnections below observed concurrency
- **Status:** pending
EOF
jq -Rs '{type:"result", result:., is_error:false, usage:{}}' < "$TMP/hyp.txt" > "$TMP/raw-pass-1.json"
python3 "$LOOP/loop_lib.py" parse --parser debug-hypotheses "$TMP/raw-pass-1.json" > "$TMP/findings.json" 2>"$TMP/parse.err"

N="$(jq 'length' "$TMP/findings.json" 2>/dev/null || echo 0)"
if [ "$N" = "3" ]; then pass "debug-hypotheses parses three blocks across both heading punctuations"
else fail "hypothesis block count: expected 3, got $N ($(cat "$TMP/parse.err"))"; fi

if [ "$(jq -r '.[0].title' "$TMP/findings.json")" = "cacheKey omits the tenant id, so a role change leaves a stale profile cached" ]; then
  pass "the mechanism rides in the title"
else fail "title: got $(jq -r '.[0].title' "$TMP/findings.json")"; fi

if [ "$(jq -r '.[0].file' "$TMP/findings.json")" = "src/cache/user.ts" ] \
   && [ "$(jq -r '.[0].line_start' "$TMP/findings.json")" = "42" ] \
   && [ "$(jq -r '.[0].line_end' "$TMP/findings.json")" = "48" ]; then
  pass "Targeted: supplies path and line range"
else fail "Targeted extraction: got $(jq -c '.[0]|{file,line_start,line_end}' "$TMP/findings.json")"; fi

# H1's Mechanism text names src/cache/redis.ts — H2's real site. If the parser
# harvested paths from prose, H1 would point at H2's file and the judge would
# score two distinct hypotheses as one location.
if [ "$(jq -r '.[0].file' "$TMP/findings.json")" != "src/cache/redis.ts" ]; then
  pass "a path mentioned only in the mechanism prose is not taken as the site"
else fail "H1 harvested H2's path out of the Mechanism line"; fi

if [ "$(jq -r '.[1].file' "$TMP/findings.json")" = "src/cache/redis.ts" ]; then
  pass "two hypotheses in the same subsystem keep distinct sites"
else fail "H2 site: got $(jq -r '.[1].file' "$TMP/findings.json")"; fi

if [ "$(jq -r '.[1].title' "$TMP/findings.json")" = "the TTL outlives the session, so entries survive invalidation" ]; then
  pass "H<N>. punctuation parses the same as H<N>:"
else fail "H2 title: got $(jq -r '.[1].title' "$TMP/findings.json")"; fi

# A run that reports a tested status has violated the read-only preamble. It has
# to reach the judge so the violation is scored, not swallowed by the parser.
if [ "$N" = "3" ] && jq -e '.[1].body|test("confirmed")' "$TMP/findings.json" >/dev/null; then
  pass "a non-pending Status is emitted rather than dropped"
else fail "the confirmed-status block was dropped or lost its status"; fi

if [ "$(jq -r '.[0].has_evidence' "$TMP/findings.json")" = "true" ] \
   && [ "$(jq -r '.[2].has_evidence' "$TMP/findings.json")" = "false" ]; then
  pass "has_evidence tracks the Evidence For line"
else fail "has_evidence: got $(jq -c '[.[].has_evidence]' "$TMP/findings.json")"; fi

# ---- 4. judge_framing replaces the defect wording ----
cat > "$TMP/rubric.json" <<'EOF'
{"version":1,"negative":false,"items":[
 {"id":"gt-1","file":"src/cache/user.ts","lines":[42,48],"class":"root-cause","severity":"HIGH",
  "must_find":true,"description":"cacheKey omits tenantId"}]}
EOF
python3 "$LOOP/loop_lib.py" judgeprompt "$TMP/rubric.json" "$TMP/findings.json" \
  "$LOOP/modules/debug/target.json" > "$TMP/p-debug.txt"
if grep -q 'competing root-cause hypotheses' "$TMP/p-debug.txt" \
   && ! grep -q 'known ground-truth defect list' "$TMP/p-debug.txt"; then
  pass "debug judge_framing replaces the defect-grading wording"
else fail "debug judge_framing did not take effect"; fi

if grep -q 'restates the symptom' "$TMP/p-debug.txt"; then
  pass "the match rule tells the judge a symptom restatement is not a match"
else fail "match rule lost the symptom-restatement clause"; fi

# ---- 5. an unmeasured noise floor blocks the noise axis ----
if [ "$(jq -r '.noise_floor' "$LOOP/modules/debug/target.json")" = "null" ]; then
  pass "debug ships with noise_floor unmeasured until its A-vs-A runs"
else fail "noise_floor was set without an A-vs-A on record"; fi

mk_run() { # <dir> <noise>
  mkdir -p "$1"
  jq -n '{module:"debug", task_manifest:[{id:"t1",version:1}]}' > "$1/spec.json"
  jq -n --argjson nz "$2" '{rows:[{task:"t1",rubric_version:1,recall_must:1,recall_all:1,
      recall_weighted:1,noise:$nz,noise_strict:$nz,nitpick:0,plausible_real:0,findings_total:3,
      tokens_in:0,tokens_out:0,pass:true}],
      mean:{recall_must:1,noise:$nz},reducers:{pass_rate:1},contested:[]}' > "$1/metrics.json"
}
# The floor gates a noise IMPROVEMENT claim, so the candidate has to be the
# quieter arm — a candidate that is noisier falls through to the tie branch and
# never reaches this guard.
mk_run "$TMP/cand" 0
mk_run "$TMP/champ" 4
OUT="$(bash "$LOOP/compare.sh" "$TMP/cand" "$TMP/champ" 2>&1 || true)"
if printf '%s' "$OUT" | grep -q 'no measured noise floor'; then
  pass "compare.sh refuses a noise win while noise_floor is unmeasured"
else fail "compare.sh read the noise axis with no measured floor: $OUT"; fi

# ---- 6. champion_sync sections still resolve ----
SEC_FAIL=0
while IFS=$'\t' read -r from section; do
  [ -n "$section" ] || continue
  if ! grep -qF "## $section" "$REPO_ROOT/$from"; then
    fail "champion_sync section '## $section' no longer exists in $from"
    SEC_FAIL=1
  fi
done < <(jq -r '.champion_sync[] | select(.section) | [.from, .section] | @tsv' \
           "$LOOP/modules/debug/target.json")
[ "$SEC_FAIL" -eq 0 ] && pass "every champion_sync section resolves to a real heading"

while IFS= read -r from; do
  [ -f "$REPO_ROOT/$from" ] || fail "champion_sync source missing: $from"
done < <(jq -r '.champion_sync[].from' "$LOOP/modules/debug/target.json")
pass "every champion_sync source file exists"

echo
echo "Tests run:    $TESTS_RUN"
echo "Tests failed: $TESTS_FAILED"
[ "$TESTS_FAILED" -eq 0 ]
