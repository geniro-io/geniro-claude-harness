#!/usr/bin/env bash
# Contract tests for the recon module's additions to evals/loop.
#
# Run: bash tests/evals/recon-module.sh   (auto-discovered by tests/run-all.sh)
# Exits non-zero on any failure. No network, no paid calls.
#
# Contracts under test:
#   1. `recon-items` parses the Phase 1 agents' OWN report schemas — one finding
#      per bullet, section heading kept in the title, path extracted from the
#      backtick token, orchestrator-summary prose excluded except change_scope
#      and Risk flags.
#   2. A dotted SYMBOL (`req.tenantId`) is not mistaken for a file path.
#   3. `polarity: "absence"` inverts the found-test in metrics, and reports the
#      real failures in missed_must.
#   4. Per-module `judge_framing` changes the prompt wording, and a module that
#      declares none gets output byte-identical to the pre-knob prompt — the
#      property that keeps review/spec-check/partition baselines comparable.
#   5. compare.sh's rubric-version guard reads the version each run was SCORED
#      under (metrics rows), not the one it was staged under.
#   6. stage-task.sh restores a `dot-geniro/` fixture directory to `.geniro/`.
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
LOOP="$REPO_ROOT/evals/loop"
TMP="$(cd "$(mktemp -d)" && pwd -P)"
trap 'rm -rf "$TMP"' EXIT

TESTS_RUN=0
TESTS_FAILED=0
pass() { TESTS_RUN=$((TESTS_RUN + 1)); echo "PASS: $1"; }
fail() { TESTS_RUN=$((TESTS_RUN + 1)); TESTS_FAILED=$((TESTS_FAILED + 1)); echo "FAIL: $1" >&2; }

# ---- 1 + 2. recon-items parser ----
cat > "$TMP/report.txt" <<'EOF'
## Codebase Exploration Report — spec "x"

### Likely-Touched Files
- `src/routes/export.ts:10-14` — the route the limiter attaches to
- `src/lib/redis.ts:6` — TTL primitive

### Reuse Inventory
- REUSE-AS-IS: `throttle` at `src/middleware/throttle.ts:20` — already per-tenant capable
- NO-ANALOGUE: a delivery record — nothing persists one

### Summary for Orchestrator
- change_scope: small
- Risk flags: auth boundary via `req.tenantId`
- Some prose bullet the rubric cannot score
- Context loaded: search-policy=absent
EOF
jq -Rs '{type:"result", result:., is_error:false, usage:{}}' < "$TMP/report.txt" > "$TMP/raw-explorer.json"
python3 "$LOOP/loop_lib.py" parse --parser recon-items "$TMP/raw-explorer.json" > "$TMP/findings.json" 2>"$TMP/parse.err"

N="$(jq 'length' "$TMP/findings.json" 2>/dev/null || echo 0)"
# 2 touched + 2 reuse + change_scope + Risk flags = 6; prose and Context loaded excluded.
if [ "$N" = "6" ]; then pass "recon-items parses bullets and excludes summary prose (6)"
else fail "recon-items bullet count: expected 6, got $N"; fi

if [ "$(jq -r '.[0].title' "$TMP/findings.json")" = "Likely-Touched Files: \`src/routes/export.ts:10-14\` — the route the limiter attaches to" ]; then
  pass "section heading rides in the title"
else fail "section heading missing from title: $(jq -r '.[0].title' "$TMP/findings.json")"; fi

if [ "$(jq -r '.[0].file' "$TMP/findings.json")" = "src/routes/export.ts" ] \
   && [ "$(jq -r '.[0].line_start' "$TMP/findings.json")" = "10" ]; then
  pass "path and line range extracted from the backtick token"
else fail "path extraction: got $(jq -c '.[0]|{file,line_start,line_end}' "$TMP/findings.json")"; fi

# The reuse row cites the helper name first and its location second; the
# location is what the rubric matches on.
if [ "$(jq -r '.[2].file' "$TMP/findings.json")" = "src/middleware/throttle.ts" ]; then
  pass "reuse row skips the bare symbol and takes the file:line"
else fail "reuse row file: got $(jq -r '.[2].file' "$TMP/findings.json")"; fi

# `req.tenantId` is a dotted symbol, not a path — it must not become .file.
RISK_FILE="$(jq -r '.[]|select(.title|startswith("Summary for Orchestrator: Risk flags"))|.file' "$TMP/findings.json")"
if [ "$RISK_FILE" = "null" ]; then pass "dotted symbol req.tenantId is not read as a file path"
else fail "dotted symbol taken as path: $RISK_FILE"; fi

if jq -e '[.[]|select(.title|test("change_scope"))]|length == 1' "$TMP/findings.json" >/dev/null; then
  pass "change_scope survives the summary-prose filter"
else fail "change_scope was filtered out of the summary"; fi

# ---- 3. polarity: absence inverts the found-test ----
cat > "$TMP/abs-rubric.json" <<'EOF'
{"version":1,"negative":false,"items":[
 {"id":"gt-1","file":"a.ts","lines":[1,1],"class":"x","severity":"HIGH","must_find":true,
  "description":"must be surfaced"},
 {"id":"gt-2","file":"b.md","lines":[1,1],"class":"y","severity":"HIGH","must_find":true,
  "polarity":"absence","description":"must NOT be claimed"}]}
EOF
echo '{"id":"t"}' > "$TMP/task.json"
echo '{"matches":[{"gt_id":"gt-1","finding_ids":["F1"]},{"gt_id":"gt-2","finding_ids":[]}],"residue":[]}' > "$TMP/m-good.json"
echo '{"matches":[{"gt_id":"gt-1","finding_ids":["F1"]},{"gt_id":"gt-2","finding_ids":["F2"]}],"residue":[]}' > "$TMP/m-bad.json"

G="$(python3 "$LOOP/loop_lib.py" metrics "$TMP/task.json" "$TMP/abs-rubric.json" "$TMP/findings.json" "$TMP/m-good.json" "$TMP" | jq -c '[.recall_must,(.missed_must|length)]')"
B="$(python3 "$LOOP/loop_lib.py" metrics "$TMP/task.json" "$TMP/abs-rubric.json" "$TMP/findings.json" "$TMP/m-bad.json"  "$TMP" | jq -c '[.recall_must,(.missed_must|length)]')"
if [ "$G" = "[1.0,0]" ]; then pass "absence item satisfied when nothing matched it"
else fail "absence satisfied case: expected [1.0,0], got $G"; fi
if [ "$B" = "[0.5,1]" ]; then pass "absence item fails when a finding asserts it, and is named in missed_must"
else fail "absence failed case: expected [0.5,1], got $B"; fi

if python3 "$LOOP/loop_lib.py" judgeprompt "$TMP/abs-rubric.json" "$TMP/findings.json" \
     "$LOOP/modules/recon/target.json" | grep -q 'polarity'; then
  pass "judge prompt carries the absence rule when an item declares it"
else fail "judge prompt omitted the absence rule"; fi

# ---- 4. judge_framing: overridden for recon, byte-identical without it ----
cat > "$TMP/plain-rubric.json" <<'EOF'
{"version":1,"negative":false,"items":[
 {"id":"gt-1","file":"a.ts","lines":[1,1],"class":"x","severity":"HIGH","must_find":true,"description":"d"}]}
EOF
python3 "$LOOP/loop_lib.py" judgeprompt "$TMP/plain-rubric.json" "$TMP/findings.json" > "$TMP/p-noarg.txt"
python3 "$LOOP/loop_lib.py" judgeprompt "$TMP/plain-rubric.json" "$TMP/findings.json" "$LOOP/modules/review/target.json" > "$TMP/p-review.txt"
python3 "$LOOP/loop_lib.py" judgeprompt "$TMP/plain-rubric.json" "$TMP/findings.json" "$LOOP/modules/recon/target.json" > "$TMP/p-recon.txt"

if cmp -s "$TMP/p-noarg.txt" "$TMP/p-review.txt"; then
  pass "a module with no judge_framing gets the byte-identical legacy prompt"
else fail "judge_framing default drifted — standing baselines are no longer comparable"; fi
if grep -q 'known ground-truth defect list' "$TMP/p-noarg.txt"; then
  pass "legacy prompt still says 'defect list'"
else fail "legacy prompt wording changed"; fi
if grep -q 'reconnaissance report' "$TMP/p-recon.txt" && ! grep -q 'known ground-truth defect list' "$TMP/p-recon.txt"; then
  pass "recon judge_framing replaces the defect-grading wording"
else fail "recon judge_framing did not take effect"; fi

# ---- 5. compare.sh guards on the SCORED version, not the staged one ----
mk_run() { # <dir> <staged-version> <scored-version>
  mkdir -p "$1"
  jq -n --argjson sv "$2" '{module:"recon", task_manifest:[{id:"t1",version:$sv}]}' > "$1/spec.json"
  jq -n --argjson cv "$3" '{rows:[{task:"t1",rubric_version:$cv,recall_must:1,recall_all:1,
      recall_weighted:1,noise:0,noise_strict:0,nitpick:0,plausible_real:0,findings_total:1,
      tokens_in:0,tokens_out:0,pass:true}],
      mean:{recall_must:1,noise:0},reducers:{pass_rate:1},contested:[]}' > "$1/metrics.json"
}
mk_run "$TMP/rc" 1 2      # staged v1, re-scored under v2
mk_run "$TMP/rb" 1 2      # same
if bash "$LOOP/compare.sh" "$TMP/rc" "$TMP/rb" >/dev/null 2>&1; then
  pass "re-scored runs with a stale staged manifest still compare"
else fail "guard false-blocked two runs scored under the same rubric version"; fi

mk_run "$TMP/rc2" 1 3     # staged v1, scored v3
mk_run "$TMP/rb2" 1 2     # staged v1, scored v2  <- the dangerous case
if bash "$LOOP/compare.sh" "$TMP/rc2" "$TMP/rb2" >/dev/null 2>&1; then
  fail "guard MISSED a real scored-version mismatch"
else pass "guard fires when the two runs were scored under different versions"; fi

# ---- 6. stage-task.sh restores dot-geniro/ ----
TASK="$TMP/task-fixture"
mkdir -p "$TASK/tree/dot-geniro/knowledge" "$TASK/tree/src"
echo '{"k":1}' > "$TASK/tree/dot-geniro/knowledge/learnings.jsonl"
echo 'export const a = 1;' > "$TASK/tree/src/a.ts"
echo '# spec' > "$TASK/spec.md"
cat > "$TASK/task.json" <<'EOF'
{ "id": "fx", "mode": "spec", "tree_dir": "tree", "spec": "spec.md", "lang": "typescript" }
EOF
bash "$LOOP/stage-task.sh" "$TASK" "$TMP/staged" >/dev/null 2>&1
if [ -f "$TMP/staged/tree/.geniro/knowledge/learnings.jsonl" ] && [ ! -d "$TMP/staged/tree/dot-geniro" ]; then
  pass "stage-task.sh renames dot-geniro/ to .geniro/"
else fail "dot-geniro/ was not restored to .geniro/ at stage time"; fi

echo
echo "Tests run:    $TESTS_RUN"
echo "Tests failed: $TESTS_FAILED"
[ "$TESTS_FAILED" -eq 0 ]
