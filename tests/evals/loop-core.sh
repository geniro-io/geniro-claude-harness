#!/usr/bin/env bash
# Core contract tests for evals/loop — the v2 module-agnostic eval stand.
#
# Run: bash tests/evals/loop-core.sh   (auto-discovered by tests/run-all.sh)
# Exits non-zero on any failure. No network, no paid calls: the driver test
# uses adapters/mock.sh.
#
# Contracts under test:
#   1. run.sh drives a sweep end-to-end via an adapter, writes spec.json with
#      the rubric-version manifest, and serves identical calls from cache on
#      a re-run (content-keyed: model + task@version + prompt hash).
#   2. score.sh finish computes per-trial pass from the module's pass_expr
#      (negative_pass_expr for negative tasks) and reduces trials into
#      pass_rate / pass@k / pass^k.
#   3. compare.sh hard-fails (exit 65) when paired tasks were scored under
#      different rubric versions, and emits verdict + MDE when versions match.
#   4. loop_lib.py accepts a legacy bare-array rubric and splits noise vs
#      nitpick in metrics.
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
LOOP="$REPO_ROOT/evals/loop"
TMP="$(cd "$(mktemp -d)" && pwd -P)"
trap 'rm -rf "$TMP"' EXIT

TESTS_RUN=0
TESTS_FAILED=0
pass() { TESTS_RUN=$((TESTS_RUN + 1)); echo "PASS: $1"; }
fail() { TESTS_RUN=$((TESTS_RUN + 1)); TESTS_FAILED=$((TESTS_FAILED + 1)); echo "FAIL: $1" >&2; }

# ---- fixture: a minimal one-task benchmark (positive) + the shipped negative task ----
TASKS="$TMP/tasks"
mkdir -p "$TASKS/pos-1/tree/src"
cat > "$TASKS/pos-1/tree/src/mock.ts" <<'EOF'
export const a = 1;
EOF
( cd "$TASKS/pos-1" && tmpd="$(mktemp -d)" && cp -R tree/. "$tmpd/" \
  && cd "$tmpd" && git init -q && git add -A \
  && git -c user.email=e@e -c user.name=t commit -qm base \
  && printf 'export const a = 1;\nexport const b = 2;\n' > src/mock.ts \
  && git add -A && git diff --cached > "$TASKS/pos-1/change.patch" && rm -rf "$tmpd" )
cat > "$TASKS/pos-1/task.json" <<'EOF'
{ "id": "pos-1", "mode": "patch", "tree_dir": "tree", "patch": "change.patch",
  "lang": "typescript", "project_context": "test fixture" }
EOF
cat > "$TASKS/pos-1/rubric.json" <<'EOF'
{ "version": 3, "negative": false,
  "items": [ { "id": "gt-1", "file": "src/mock.ts", "lines": [1, 2], "class": "planted",
               "severity": "HIGH", "must_find": true, "description": "mock defect" } ] }
EOF

# ---- 1. driver end-to-end via mock adapter + cache ----
export LOOP_CACHE_DIR="$TMP/cache"
OUT1="$TMP/run1"
if bash "$LOOP/run.sh" --module review --tasks "$TASKS" --adapter mock \
     --model mock-model --trials 1 --out "$OUT1" >/dev/null 2>&1; then
  pass "run.sh completes a mock sweep"
else
  fail "run.sh completes a mock sweep"
fi
[ "$(jq -r '.task_manifest[0] | "\(.id)@\(.version)"' "$OUT1/spec.json" 2>/dev/null)" = "pos-1@3" ] \
  && pass "spec.json pins the rubric version manifest" \
  || fail "spec.json pins the rubric version manifest"
N_RAW="$(ls "$OUT1"/results/pos-1/trial-1/raw-*.json 2>/dev/null | wc -l | tr -d ' ')"
[ "$N_RAW" = "$(jq '.facets | length' "$LOOP/modules/review/target.json")" ] \
  && pass "one raw result per facet" || fail "one raw result per facet (got $N_RAW)"
OUT2="$TMP/run2"
LOG2="$(bash "$LOOP/run.sh" --module review --tasks "$TASKS" --adapter mock \
          --model mock-model --trials 1 --out "$OUT2" 2>&1 || true)"
echo "$LOG2" | grep -q '\[cache\]' \
  && pass "identical re-run is served from cache" \
  || fail "identical re-run is served from cache"

# ---- 2. score.sh finish: pass exprs + reducers over a crafted run ----
RUN="$TMP/scored"
mkdir -p "$RUN/stage/pos-1" "$RUN/stage/neg-1"
cp "$TASKS/pos-1/task.json" "$RUN/stage/pos-1/task.json"
mkdir -p "$TASKS/neg-1"
cat > "$TASKS/neg-1/task.json" <<'EOF'
{ "id": "neg-1", "mode": "patch", "tree_dir": "tree", "patch": "change.patch" }
EOF
cat > "$TASKS/neg-1/rubric.json" <<'EOF'
{ "version": 1, "negative": true, "items": [] }
EOF
cp "$TASKS/neg-1/task.json" "$RUN/stage/neg-1/task.json"
jq -n --arg tasks "$TASKS" '{module:"review", tasks:$tasks, task_manifest:[
  {id:"pos-1",version:3},{id:"neg-1",version:1}]}' > "$RUN/spec.json"
mk_trial() { # task trial findings match
  local d="$RUN/results/$1/$2"
  mkdir -p "$d"
  printf '%s' "$3" > "$d/findings.json"
  printf '%s' "$4" > "$d/match.json"
}
F1='[{"id":"F1","severity":"HIGH","title":"t","facet":"bugs","file":"src/mock.ts","line_start":1,"line_end":2,"body":"x"}]'
mk_trial pos-1 trial-1 "$F1" '{"matches":[{"gt_id":"gt-1","finding_ids":["F1"]}],"residue":[]}'
mk_trial pos-1 trial-2 "$F1" '{"matches":[{"gt_id":"gt-1","finding_ids":[]}],"residue":[{"finding_id":"F1","bucket":"noise","reason":"r"}]}'
mk_trial neg-1 trial-1 "$F1" '{"matches":[],"residue":[{"finding_id":"F1","bucket":"nitpick","reason":"r"}]}'
mk_trial neg-1 trial-2 "$F1" '{"matches":[],"residue":[{"finding_id":"F1","bucket":"noise","reason":"r"}]}'
if bash "$LOOP/score.sh" "$RUN" --phase finish >/dev/null 2>&1; then
  pass "score.sh finish runs on the crafted run"
else
  fail "score.sh finish runs on the crafted run"
fi
read -r PR PAK PHK <<EOF2
$(jq -r '.reducers | "\(.pass_rate) \(.pass_at_k) \(.pass_hat_k)"' "$RUN/metrics.json" 2>/dev/null)
EOF2
[ "$PR" = "0.5" ] && pass "pass_rate reduces to 0.5" || fail "pass_rate=$PR (want 0.5)"
[ "$PAK" = "1" ] && pass "pass@k: every task passes at least once" || fail "pass_at_k=$PAK (want 1)"
[ "$PHK" = "0" ] && pass "pass^k: no task passes every trial" || fail "pass_hat_k=$PHK (want 0)"
jq -e '.rows[] | select(.task=="neg-1" and .trial=="trial-1") | .nitpick == 1 and .noise_strict == 0 and .pass' \
  "$RUN/metrics.json" >/dev/null 2>&1 \
  && pass "negative task: nitpick-only trial passes, split from strict noise" \
  || fail "negative task: nitpick-only trial passes, split from strict noise"

# ---- 3. compare.sh rubric-version guard + MDE ----
mkdir -p "$TMP/cand" "$TMP/base"
jq -n --arg tasks "$TASKS" '{module:"review", tasks:$tasks,
  task_manifest:[{id:"pos-1",version:3}]}' > "$TMP/cand/spec.json"
jq -n --arg tasks "$TASKS" '{module:"review", tasks:$tasks,
  task_manifest:[{id:"pos-1",version:2}]}' > "$TMP/base/spec.json"
ROWS='{"rows":[{"task":"pos-1","trial":"trial-1","recall_must":1,"noise":0},{"task":"t2","trial":"trial-1","recall_must":0.5,"noise":1},{"task":"t3","trial":"trial-1","recall_must":1,"noise":2}]}'
printf '%s' "$ROWS" > "$TMP/cand/metrics.json"
printf '%s' "$ROWS" > "$TMP/base/metrics.json"
bash "$LOOP/compare.sh" "$TMP/cand" "$TMP/base" >/dev/null 2>&1
[ "$?" = "65" ] && pass "compare.sh exits 65 on rubric-version mismatch" \
  || fail "compare.sh exits 65 on rubric-version mismatch"
jq -n --arg tasks "$TASKS" '{module:"review", tasks:$tasks,
  task_manifest:[{id:"pos-1",version:3}]}' > "$TMP/base/spec.json"
VERDICT="$(bash "$LOOP/compare.sh" "$TMP/cand" "$TMP/base" 2>/dev/null)"
echo "$VERDICT" | jq -e '.verdict and (.recall_must | has("mde"))' >/dev/null 2>&1 \
  && pass "matched versions: verdict + MDE emitted" \
  || fail "matched versions: verdict + MDE emitted"

# ---- 4. loop_lib: legacy bare-array rubric + noise/nitpick split ----
printf '[{"id":"gt-1","severity":"HIGH","must_find":true,"description":"d"}]' > "$TMP/legacy.json"
printf '%s' "$F1" > "$TMP/f.json"
python3 "$LOOP/loop_lib.py" judgeprompt "$TMP/legacy.json" "$TMP/f.json" > "$TMP/jp.txt" 2>/dev/null \
  && grep -q "gt-1" "$TMP/jp.txt" \
  && pass "judgeprompt accepts a legacy bare-array rubric" \
  || fail "judgeprompt accepts a legacy bare-array rubric"

echo
echo "loop-core: $TESTS_RUN run, $TESTS_FAILED failed"
[ "$TESTS_FAILED" -eq 0 ]
