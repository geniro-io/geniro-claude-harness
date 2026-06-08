#!/usr/bin/env bash
# Integration tests for evals/run-suite.sh — the Phase-C §6 orchestrator (plan §6, §16).
#
# Run: bash tests/evals/run-suite.sh   (auto-discovered by tests/run-all.sh)
# Exits non-zero on any failure.
#
# Plugin-developer / eval tooling only — not shipped to user projects.
#
# Contract under test: run-suite drives a suite version-vs-version, grades, POSITION-SWAP compares,
# aggregates, and (with --ingest) appends a ledger row. The real driver/`claude` are spending,
# multi-minute operations, so the loop is exercised here with FAKES injected via EVAL_DRIVER_CMD /
# EVAL_CLAUDE_CMD / EVAL_FIXTURE_CMD — nothing real runs, nothing is spent. Verifies:
#   - --dry-run prints the matrix and spends/writes nothing
#   - the full loop builds the benchmark workspace + a conforming benchmark.json
#   - the POSITION-SWAP wrapper cancels a pure position-biased judge (always-"A" → primary_value 0.5)
#   - a judge that consistently prefers the candidate's content in BOTH orders → primary_value 1.0
#   - --ingest closes the chain to a committed row; A-vs-A comes back a TIE (gate does not fire)

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
RS="$REPO_ROOT/evals/run-suite.sh"
SUITE="$REPO_ROOT/evals/suites/plan/evals.json"

TMPDIR_BASE="$(cd "$(mktemp -d)" && pwd -P)"
ORIGINAL_PWD="$PWD"
trap 'cd "$ORIGINAL_PWD"; rm -rf "$TMPDIR_BASE"' EXIT

TESTS_RUN=0
TESTS_FAILED=0
pass() { TESTS_RUN=$((TESTS_RUN + 1)); echo "PASS: $1"; }
fail() { TESTS_RUN=$((TESTS_RUN + 1)); TESTS_FAILED=$((TESTS_FAILED + 1)); echo "FAIL: $1" >&2; }

# --- fakes -------------------------------------------------------------------
BIN="$TMPDIR_BASE/bin"; mkdir -p "$BIN"

# Fake driver: write a result.json into --out, and a spec.md (content = the --plugin-ref, so the
# candidate and baseline outputs are content-distinguishable) into --cwd's .geniro/planning.
cat > "$BIN/fake-driver.sh" <<'EOF'
#!/usr/bin/env bash
out=""; cwd=""; ref=""
while [ $# -gt 0 ]; do
  case "$1" in
    --out) out="$2"; shift 2;; --cwd) cwd="$2"; shift 2;; --plugin-ref) ref="$2"; shift 2;;
    *) shift;;
  esac
done
mkdir -p "$out"
printf '{"completed":true,"duration_ms":30000,"model_usage":{"claude-opus-4-8":{"inputTokens":1000,"outputTokens":500,"cacheReadInputTokens":9000,"cacheCreationInputTokens":200,"costUSD":0}},"usage":null}\n' > "$out/result.json"
mkdir -p "$cwd/.geniro/planning/task-x"
printf '# spec for ref %s\n\n1. Objective ...\n' "$ref" > "$cwd/.geniro/planning/task-x/spec.md"
EOF
chmod +x "$BIN/fake-driver.sh"

# Fake fixture: print a fresh target dir on the last line.
cat > "$BIN/fake-fixture.sh" <<'EOF'
#!/usr/bin/env bash
d="$(mktemp -d "${TMPDIR:-/tmp}/fake-target-XXXXXX")"
echo "$d"
EOF
chmod +x "$BIN/fake-fixture.sh"

# Fake claude: emulate `claude -p ... --output-format json` → {"result":"<json>"}.
# Grader prompt → a grading.json; comparator prompt → a comparison with a winner chosen by FAKE_CMP_MODE:
#   tie     → always TIE
#   alwaysA → always "A"   (a pure position-biased judge)
#   content → "A"/"B" = whichever Output block contains $FAKE_WIN_REF
# FAKE_TRAILING_PROSE=1 appends prose after the JSON (the common "JSON only"-violation); FAKE_LOWER=1
# emits a lowercase winner. Both must NOT corrupt the result (HIGH + LOW review findings).
cat > "$BIN/fake-claude.sh" <<'EOF'
#!/usr/bin/env bash
prompt=""
while [ $# -gt 0 ]; do case "$1" in -p) prompt="$2"; shift 2;; *) shift;; esac; done
emit() {
  local inner="$1"
  if [ -n "${FAKE_TRAILING_PROSE:-}" ]; then inner="$inner

That concludes my analysis. The verdict above is final — extra prose the model was told NOT to add."; fi
  jq -n --arg r "$inner" '{result:$r}'
}
if printf '%s' "$prompt" | grep -q "Blind Comparator"; then
  mode="${FAKE_CMP_MODE:-tie}"; winner="TIE"
  case "$mode" in
    alwaysA) winner="A";;
    tie) winner="TIE";;
    content)
      blockA="$(printf '%s' "$prompt" | awk '/## Output A/{f=1;next} /## Output B/{f=0} f')"
      if printf '%s' "$blockA" | grep -q "${FAKE_WIN_REF:-__none__}"; then winner="A"; else winner="B"; fi;;
  esac
  [ -n "${FAKE_LOWER:-}" ] && winner="$(printf '%s' "$winner" | tr 'A-Z' 'a-z')"
  emit "$(jq -nc --arg w "$winner" '{winner:$w,reasoning:"fake"}')"
else
  emit "$(jq -nc '{expectations:[{text:"e0",passed:true},{text:"e1",passed:true}],summary:{passed:2,total:2,pass_rate:1.0}}')"
fi
EOF
chmod +x "$BIN/fake-claude.sh"

export EVAL_DRIVER_CMD="bash $BIN/fake-driver.sh"
export EVAL_FIXTURE_CMD="bash $BIN/fake-fixture.sh"
export EVAL_CLAUDE_CMD="bash $BIN/fake-claude.sh"

run_rs() { bash "$RS" "$@"; }

# ===== 1. --dry-run prints the matrix, writes nothing, spends nothing =====
WS="$TMPDIR_BASE/ws-dry"
out="$(run_rs --skill geniro:plan --suite "$SUITE" --candidate AAA --baseline AAA \
      --task-ids 1,2 --trials 2 --out "$WS" --dry-run 2>&1)"; rc=$?
if [ "$rc" -eq 0 ] && printf '%s' "$out" | grep -q "DRY RUN" \
   && printf '%s' "$out" | grep -q "A-vs-A null calibration" \
   && printf '%s' "$out" | grep -q "8 driver runs" \
   && [ ! -e "$WS/benchmark.json" ] && [ ! -e "$WS/meta.json" ]; then
  pass "--dry-run: prints matrix (8 driver runs for 2 tasks×2 trials×2 sides), A-vs-A note, writes nothing"
else
  fail "--dry-run wrong — rc=$rc wrote_ws=$([ -e "$WS/meta.json" ] && echo yes || echo no); out: $(printf '%s' "$out" | tr '\n' '|' | cut -c1-200)"
fi

# ===== 2. Full loop (A-vs-A, fakes): workspace + conforming benchmark.json, grading present =====
WS="$TMPDIR_BASE/ws-full"
FAKE_CMP_MODE=tie run_rs --skill geniro:plan --suite "$SUITE" --candidate AAA --baseline AAA \
  --task-ids 1 --trials 1 --out "$WS" >/dev/null 2>&1; rc=$?
ok=1
[ -f "$WS/eval-1/candidate/run-1/result.json" ] || ok=0
[ -f "$WS/eval-1/candidate/run-1/spec.md" ] || ok=0
[ -f "$WS/eval-1/candidate/run-1/grading.json" ] || ok=0
[ -f "$WS/eval-1/baseline/run-1/result.json" ] || ok=0
[ -f "$WS/eval-1/comparison.json" ] || ok=0
[ -f "$WS/benchmark.json" ] || ok=0
pv=$(jq -r '.tasks[0].primary_value' "$WS/benchmark.json" 2>/dev/null)
ntasks=$(jq -r '.tasks|length' "$WS/benchmark.json" 2>/dev/null)
cin=$(jq -r '.tasks[0].candidate.input_tokens' "$WS/benchmark.json" 2>/dev/null)
if [ "$rc" -eq 0 ] && [ "$ok" -eq 1 ] && [ "$ntasks" = "1" ] && [ "$pv" = "0.5" ] && [ "$cin" = "1000" ]; then
  pass "full loop: workspace + benchmark.json built (1 task, TIE→primary_value 0.5, candidate tokens summed)"
else
  fail "full loop wrong — rc=$rc files_ok=$ok ntasks=$ntasks pv=$pv cin=$cin"
fi

# ===== 3. Position-swap cancels a PURE position-biased judge (always-'A' → primary_value 0.5) =====
WS="$TMPDIR_BASE/ws-bias"
FAKE_CMP_MODE=alwaysA run_rs --skill geniro:plan --suite "$SUITE" --candidate AAA --baseline BBB \
  --task-ids 1 --trials 1 --out "$WS" >/dev/null 2>&1
pv=$(jq -r '.tasks[0].primary_value' "$WS/benchmark.json" 2>/dev/null)
if [ "$pv" = "0.5" ]; then
  pass "position-swap robustness: a judge that always picks 'A' yields primary_value 0.5 (no spurious win)"
else
  fail "position-swap did not cancel a position-biased judge — primary_value=$pv (expected 0.5)"
fi

# ===== 4. A genuine content win in BOTH orders → primary_value 1.0 =====
WS="$TMPDIR_BASE/ws-win"
FAKE_CMP_MODE=content FAKE_WIN_REF=CANDREF run_rs --skill geniro:plan --suite "$SUITE" \
  --candidate CANDREF --baseline BASEREF --task-ids 1 --trials 1 --out "$WS" >/dev/null 2>&1
pv=$(jq -r '.tasks[0].primary_value' "$WS/benchmark.json" 2>/dev/null)
if [ "$pv" = "1" ]; then
  pass "genuine win: candidate preferred in both swapped orders → primary_value 1.0"
else
  fail "content-win primary_value wrong — got $pv (expected 1)"
fi

# ===== 5. --ingest closes the chain; A-vs-A is a committed TIE (gate does not fire) =====
SB="$(mktemp -d "$TMPDIR_BASE/sb.XXXX")"
git -C "$SB" init -q; git -C "$SB" config user.email e@e.l; git -C "$SB" config user.name e
git -C "$SB" commit --allow-empty -q -m base; REF="$(git -C "$SB" rev-parse HEAD)"
mkdir -p "$SB/evals"; : > "$SB/evals/history.jsonl"; git -C "$SB" add evals/history.jsonl; git -C "$SB" commit -q -m seed
WS="$TMPDIR_BASE/ws-ingest"
( cd "$SB" && FAKE_CMP_MODE=tie EVAL_DRIVER_CMD="bash $BIN/fake-driver.sh" \
   EVAL_FIXTURE_CMD="bash $BIN/fake-fixture.sh" EVAL_CLAUDE_CMD="bash $BIN/fake-claude.sh" \
   bash "$RS" --skill geniro:plan --suite "$SUITE" --candidate "$REF" --baseline "$REF" \
     --task-ids 1,2 --trials 1 --out "$WS" --ingest --notes "fake A-vs-A smoke" ) >/dev/null 2>&1
irc=$?
row="$(tail -n1 "$SB/evals/history.jsonl" 2>/dev/null)"
sig=$(printf '%s' "$row" | jq -r '.significant_on_primary' 2>/dev/null)
beats=$(printf '%s' "$row" | jq -r '.primary_beats_null' 2>/dev/null)
ntasks=$(printf '%s' "$row" | jq -r '.tasks' 2>/dev/null)
lines=$(grep -c . "$SB/evals/history.jsonl" 2>/dev/null || echo 0)
if [ "$irc" -eq 0 ] && [ "$lines" -eq 1 ] && [ "$sig" = "false" ] && [ "$beats" = "false" ] && [ "$ntasks" = "2" ]; then
  pass "--ingest end-to-end (fakes): one ledger row, 2 tasks, A-vs-A TIE (sig=false beats=false)"
else
  fail "--ingest chain wrong — irc=$irc lines=$lines sig=$sig beats=$beats ntasks=$ntasks"
fi

# ===== 6. Usage errors: missing --suite / --candidate / bad --trials → exit 64 =====
run_rs --skill geniro:plan --candidate A --baseline A >/dev/null 2>&1; e1=$?
run_rs --skill geniro:plan --suite "$SUITE" --baseline A >/dev/null 2>&1; e2=$?
run_rs --skill geniro:plan --suite "$SUITE" --candidate A --baseline A --trials 0 >/dev/null 2>&1; e3=$?
if [ "$e1" -eq 64 ] && [ "$e2" -eq 64 ] && [ "$e3" -eq 64 ]; then
  pass "usage errors: missing --suite ($e1), missing --candidate ($e2), --trials 0 ($e3) all exit 64"
else
  fail "usage error codes wrong — no-suite=$e1 no-candidate=$e2 trials0=$e3 (want 64 each)"
fi

# ===== 7. TRAILING PROSE after the judge's JSON must NOT corrupt primary_value or drop grading =====
# Regression for the HIGH finding: a genuine content win in both orders + trailing prose must stay 1.0,
# and the candidate grading.json must still be written (expectation_pass non-empty).
WS="$TMPDIR_BASE/ws-prose"
FAKE_CMP_MODE=content FAKE_WIN_REF=CANDREF FAKE_TRAILING_PROSE=1 \
  run_rs --skill geniro:plan --suite "$SUITE" --candidate CANDREF --baseline BASEREF \
  --task-ids 1 --trials 1 --out "$WS" >/dev/null 2>&1
pv=$(jq -r '.tasks[0].primary_value' "$WS/benchmark.json" 2>/dev/null)
epl=$(jq -r '.tasks[0].expectation_pass|length' "$WS/benchmark.json" 2>/dev/null)
gok=$([ -f "$WS/eval-1/candidate/run-1/grading.json" ] && echo yes || echo no)
if [ "$pv" = "1" ] && [ "$gok" = "yes" ] && [ "${epl:-0}" -gt 0 ]; then
  pass "trailing prose: genuine win stays primary_value 1.0 + grading.json written (HIGH-bug regression)"
else
  fail "trailing prose corrupted the run — primary_value=$pv (want 1) grading=$gok expectation_pass_len=$epl"
fi

# ===== 8. A lowercase winner ('a'/'b') must be scored, not silently treated as a TIE =====
WS="$TMPDIR_BASE/ws-lower"
FAKE_CMP_MODE=content FAKE_WIN_REF=CANDREF FAKE_LOWER=1 \
  run_rs --skill geniro:plan --suite "$SUITE" --candidate CANDREF --baseline BASEREF \
  --task-ids 1 --trials 1 --out "$WS" >/dev/null 2>&1
pv=$(jq -r '.tasks[0].primary_value' "$WS/benchmark.json" 2>/dev/null)
if [ "$pv" = "1" ]; then
  pass "lowercase winner: 'a'/'b' uppercase-folded → genuine win scored 1.0, not a TIE"
else
  fail "lowercase winner mis-scored — primary_value=$pv (want 1)"
fi

echo
echo "Tests run:    $TESTS_RUN"
echo "Tests failed: $TESTS_FAILED"
[ "$TESTS_FAILED" -eq 0 ]
