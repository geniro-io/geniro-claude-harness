#!/usr/bin/env bash
# Integration tests for evals/ingest.sh — the Phase-B ingest helper (plan §8/§9, §16).
#
# Run: bash tests/evals/ingest.sh   (auto-discovered by tests/run-all.sh)
# Exits non-zero on any failure.
#
# Plugin-developer / eval tooling only — not shipped to user projects.
#
# Contract under test: ingest reads a benchmark.json (the harness/aggregate output,
# schema documented in evals/BENCHMARK-SCHEMA.md), and for a committed A/B pair:
#   - DERIVES cost = tokens × price-map.json   (subscription billing emits no $)
#   - computes the RIGHT CI per metric: Wilson for proportions (pass_rate, precision),
#     a task-clustered bootstrap for winrate / pass^k (the task is the unit of randomization)
#   - applies the primary-metric gate (a delta inside the CI is a tie, not a win)
#   - REJECTS a dirty tree / unknown ref (no fictional provenance, p-hacking guard)
#   - stamps instructions_digest + an incrementing attempt_no
#   - appends exactly one history.jsonl record + one HISTORY.md row via ledger_append.
#
# Reproducibility: the bootstrap is seeded, so the same (benchmark, seed) yields a
# byte-identical CI — a committed ledger must not jiggle on re-ingest.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
INGEST="$REPO_ROOT/evals/ingest.sh"
FIXTURE="$REPO_ROOT/evals/fixtures/benchmark.example.json"

TMPDIR_BASE="$(cd "$(mktemp -d)" && pwd -P)"
ORIGINAL_PWD="$PWD"
trap 'cd "$ORIGINAL_PWD"; rm -rf "$TMPDIR_BASE"' EXIT

TESTS_RUN=0
TESTS_FAILED=0
pass() { TESTS_RUN=$((TESTS_RUN + 1)); echo "PASS: $1"; }
fail() { TESTS_RUN=$((TESTS_RUN + 1)); TESTS_FAILED=$((TESTS_FAILED + 1)); echo "FAIL: $1" >&2; }
fcmp() { awk "BEGIN{ exit !($1) }"; }

# Build a clean sandbox git repo with two real commits (baseline, candidate). Sets
# SANDBOX, BASE, CAND. The benchmark file lives OUTSIDE the repo so the tree stays clean.
# A tracked empty ledger is committed so evals/ mirrors the real repo (Phase A committed the
# ledger): otherwise git collapses a fully-untracked evals/ to "?? evals/" and ingest's
# own-output exclusion — which targets the real " M evals/history.jsonl" form — wouldn't apply.
new_repo() {
  SANDBOX="$(mktemp -d "$TMPDIR_BASE/repo.XXXXXXXX")"
  git -C "$SANDBOX" init -q
  git -C "$SANDBOX" config user.email "eval@test.local"
  git -C "$SANDBOX" config user.name "Eval Test"
  git -C "$SANDBOX" commit --allow-empty -q -m baseline
  BASE="$(git -C "$SANDBOX" rev-parse HEAD)"
  git -C "$SANDBOX" commit --allow-empty -q -m candidate
  CAND="$(git -C "$SANDBOX" rev-parse HEAD)"
  mkdir -p "$SANDBOX/evals"
  : > "$SANDBOX/evals/history.jsonl"
  git -C "$SANDBOX" add evals/history.jsonl
  git -C "$SANDBOX" commit -q -m "seed ledger"
}

# A PRIMARY repo + a LINKED worktree off it (the prescribed eval-isolation layout). Sets PRIMARY,
# LINKED, BASE, CAND; the shared ledger resolves to PRIMARY via _geniro_repo_root's redirect.
new_linked() {
  PRIMARY="$(mktemp -d "$TMPDIR_BASE/primary.XXXXXXXX")"
  git -C "$PRIMARY" init -q
  git -C "$PRIMARY" config user.email "eval@test.local"
  git -C "$PRIMARY" config user.name "Eval Test"
  git -C "$PRIMARY" commit --allow-empty -q -m baseline
  BASE="$(git -C "$PRIMARY" rev-parse HEAD)"
  git -C "$PRIMARY" commit --allow-empty -q -m candidate
  CAND="$(git -C "$PRIMARY" rev-parse HEAD)"
  mkdir -p "$PRIMARY/evals"; : > "$PRIMARY/evals/history.jsonl"
  git -C "$PRIMARY" add evals/history.jsonl
  git -C "$PRIMARY" commit -q -m "seed ledger"
  LINKED="$TMPDIR_BASE/linked.$$.$RANDOM"
  git -C "$PRIMARY" worktree add -q -b "probe-linked-$RANDOM" "$LINKED" HEAD
}

# Run a command with a hard wall-clock cap; returns the command's rc, or 137 if it had to be
# killed (so a hang surfaces as a failure instead of stalling the whole suite).
with_timeout() {
  local secs="$1"; shift
  "$@" & local pid=$!
  ( sleep "$secs"; kill -9 "$pid" 2>/dev/null ) & local killer=$!
  wait "$pid" 2>/dev/null; local rc=$?
  kill "$killer" 2>/dev/null; wait "$killer" 2>/dev/null
  return "$rc"
}

LEDGER=""      # set per-run
record() { tail -n 1 "$LEDGER" 2>/dev/null; }
# grep -c prints "0" AND exits 1 on an empty (but existing) file, so a `&&…||echo 0` chain
# would emit "0\n0". Use if/else and let grep's own count stand.
ledger_lines() { if [ -f "$LEDGER" ]; then grep -c . "$LEDGER"; else echo 0; fi; }

# Run ingest with cwd=SANDBOX so _geniro_repo_root resolves to the sandbox ledger.
run_ingest() {
  local bench="$1"; shift
  LEDGER="$SANDBOX/evals/history.jsonl"
  ( cd "$SANDBOX" && bash "$INGEST" "$bench" --bootstrap-reps 2000 --seed 2026 "$@" )
}

# ===== 1. Clear-win fixture: primary gate fires (CI clears the 0.5 null) =====
new_repo
run_ingest "$FIXTURE" --candidate "$CAND" --baseline "$BASE" --notes "smoke run" >/dev/null 2>&1
rc=$?
rec="$(record)"
sig=$(printf '%s' "$rec" | jq -r '.significant_on_primary')
beats=$(printf '%s' "$rec" | jq -r '.primary_beats_null')
wr=$(printf '%s' "$rec" | jq -r '.quality_winrate_vs_baseline')
cilo=$(printf '%s' "$rec" | jq -r '.quality_ci[0]')
if [ "$rc" -eq 0 ] && [ "$(ledger_lines)" -eq 1 ] && [ "$sig" = "true" ] && [ "$beats" = "true" ] \
   && fcmp "$wr > 0.86 && $wr < 0.873" && fcmp "$cilo > 0.5"; then
  pass "clear win: significant_on_primary + primary_beats_null true, winrate≈0.867, CI lo>0.5 (wr=$wr cilo=$cilo)"
else
  fail "clear-win gate wrong — rc=$rc lines=$(ledger_lines) sig=$sig beats=$beats wr=$wr cilo=$cilo"
fi

# ===== 2. Cost DERIVED from tokens × price map (subscription emits no $) =====
cost=$(printf '%s' "$rec" | jq -r '.mean_cost_usd')
cdelta=$(printf '%s' "$rec" | jq -r '.cost_delta')
cfrom=$(printf '%s' "$rec" | jq -r '.cost_derived_from')
if fcmp "$cost > 0.470 && $cost < 0.474" && fcmp "$cdelta < 0 && $cdelta > -0.08" \
   && printf '%s' "$cfrom" | grep -q 'price-map@v1'; then
  pass "cost derived: mean_cost_usd≈0.472, cost_delta<0, cost_derived_from=price-map@v1 (cost=$cost Δ=$cdelta)"
else
  fail "cost derivation wrong — cost=$cost cdelta=$cdelta from=$cfrom"
fi

# ===== 3. Token + wall-time deltas (absolute, per §8) =====
tdelta=$(printf '%s' "$rec" | jq -r '.tokens_delta')
wdelta=$(printf '%s' "$rec" | jq -r '.time_delta')
mtok=$(printf '%s' "$rec" | jq -r '.mean_tokens')
if fcmp "$tdelta < -2000 && $tdelta > -3800" && fcmp "$wdelta > 0.5 && $wdelta < 1.0" \
   && fcmp "$mtok > 50000 && $mtok < 51200"; then
  pass "deltas: tokens_delta≈-2917 (absolute), time_delta≈+0.73s, mean_tokens≈50617 (t=$tdelta w=$wdelta)"
else
  fail "token/time deltas wrong — tokens_delta=$tdelta time_delta=$wdelta mean_tokens=$mtok"
fi

# ===== 4. Proportions use Wilson; pass_rate + precision derived =====
pr=$(printf '%s' "$rec" | jq -r '.pass_rate')
prec=$(printf '%s' "$rec" | jq -r '.precision')
prci=$(printf '%s' "$rec" | jq -r '.pass_rate_ci | length')
if fcmp "$pr > 0.93 && $pr < 0.937" && fcmp "$prec > 0.96 && $prec < 0.97" && [ "$prci" = "2" ]; then
  pass "proportions: pass_rate≈0.933, precision≈0.967, pass_rate_ci is a 2-tuple (pr=$pr prec=$prec)"
else
  fail "proportions wrong — pass_rate=$pr precision=$prec pass_rate_ci_len=$prci"
fi

# ===== 5. ci_method strings are stamped per metric (provenance) =====
qm=$(printf '%s' "$rec" | jq -r '.ci_method')
pm=$(printf '%s' "$rec" | jq -r '.pass_rate_ci_method')
if printf '%s' "$qm" | grep -q 'bootstrap-task-clustered@95%' && printf '%s' "$pm" | grep -q 'wilson@95%'; then
  pass "ci_method stamped: primary=bootstrap-task-clustered@95%, pass_rate=wilson@95%"
else
  fail "ci_method strings wrong — primary='$qm' pass_rate='$pm'"
fi

# ===== 6. instructions_digest recorded (sha256:) even when instruction files are absent =====
dig=$(printf '%s' "$rec" | jq -r '.instructions_digest')
if printf '%s' "$dig" | grep -Eq '^sha256:[0-9a-f]{64}$'; then
  pass "instructions_digest recorded as sha256:<64hex> (absent files → empty-input hash) ($dig)"
else
  fail "instructions_digest not a sha256: digest — got '$dig'"
fi

# ===== 7. attempt_no increments across candidates against the same baseline =====
new_repo
run_ingest "$FIXTURE" --candidate "$CAND" --baseline "$BASE" >/dev/null 2>&1
a1=$(record | jq -r '.attempt_no')
git -C "$SANDBOX" commit --allow-empty -q -m candidate2
CAND2="$(git -C "$SANDBOX" rev-parse HEAD)"
run_ingest "$FIXTURE" --candidate "$CAND2" --baseline "$BASE" >/dev/null 2>&1
a2=$(record | jq -r '.attempt_no')
if [ "$a1" = "1" ] && [ "$a2" = "2" ] && [ "$(ledger_lines)" -eq 2 ]; then
  pass "attempt_no increments per (skill, baseline): 1 then 2"
else
  fail "attempt_no wrong — a1=$a1 a2=$a2 lines=$(ledger_lines)"
fi

# ===== 8. Dirty working tree is REJECTED (no fictional provenance) =====
new_repo
echo "uncommitted" > "$SANDBOX/dirty.txt"
run_ingest "$FIXTURE" --candidate "$CAND" --baseline "$BASE" >/dev/null 2>&1
rc=$?
if [ "$rc" -eq 70 ] && [ "$(ledger_lines)" -eq 0 ]; then
  pass "dirty working tree rejected with the dirty-tree code rc=70, nothing written"
else
  fail "dirty tree not rejected with rc=70 — rc=$rc lines=$(ledger_lines)"
fi

# ===== 9. Unknown candidate ref is REJECTED =====
new_repo
run_ingest "$FIXTURE" --candidate "deadbeefdeadbeefdeadbeefdeadbeefdeadbeef" --baseline "$BASE" >/dev/null 2>&1
rc=$?
if [ "$rc" -eq 71 ] && [ "$(ledger_lines)" -eq 0 ]; then
  pass "unknown candidate ref rejected with the bad-ref code rc=71, nothing written"
else
  fail "unknown ref not rejected with rc=71 — rc=$rc lines=$(ledger_lines)"
fi

# ===== 10. Tie fixture (primary ≈ 0.5): gate does NOT fire =====
new_repo
tie="$TMPDIR_BASE/bench-tie.json"
jq --argjson pv '[0.50,0.45,0.55,0.50,0.48,0.52]' \
   '.tasks |= (to_entries | map(.value.primary_value = $pv[.key] | .value))' \
   "$FIXTURE" > "$tie"
run_ingest "$tie" --candidate "$CAND" --baseline "$BASE" >/dev/null 2>&1
sig=$(record | jq -r '.significant_on_primary')
beats=$(record | jq -r '.primary_beats_null')
if [ "$sig" = "false" ] && [ "$beats" = "false" ]; then
  pass "tie (primary≈0.5): significant_on_primary=false, primary_beats_null=false"
else
  fail "tie gate wrong — sig=$sig beats=$beats"
fi

# ===== 11. Significant REGRESSION: distinguishable from a tie, but NOT a win =====
new_repo
reg="$TMPDIR_BASE/bench-reg.json"
jq --argjson pv '[0.20,0.30,0.25,0.35,0.28,0.22]' \
   '.tasks |= (to_entries | map(.value.primary_value = $pv[.key] | .value))' \
   "$FIXTURE" > "$reg"
run_ingest "$reg" --candidate "$CAND" --baseline "$BASE" >/dev/null 2>&1
sig=$(record | jq -r '.significant_on_primary')
beats=$(record | jq -r '.primary_beats_null')
wr=$(record | jq -r '.quality_winrate_vs_baseline')
if [ "$sig" = "true" ] && [ "$beats" = "false" ] && fcmp "$wr < 0.5"; then
  pass "significant regression: significant_on_primary=true but primary_beats_null=false (wr=$wr)"
else
  fail "regression semantics wrong — sig=$sig beats=$beats wr=$wr"
fi

# ===== 12. Unknown executor_model → cost cannot be derived → fail fast =====
new_repo
nomodel="$TMPDIR_BASE/bench-nomodel.json"
jq '.executor_model = "gpt-9-imaginary"' "$FIXTURE" > "$nomodel"
run_ingest "$nomodel" --candidate "$CAND" --baseline "$BASE" >/dev/null 2>&1
rc=$?
if [ "$rc" -eq 72 ] && [ "$(ledger_lines)" -eq 0 ]; then
  pass "unknown executor_model rejected with the unpriced-model code rc=72 — cost cannot be faked, nothing written"
else
  fail "unknown model not rejected with rc=72 — rc=$rc lines=$(ledger_lines)"
fi

# ===== 13. Reproducible CI: same (benchmark, seed) → byte-identical quality_ci =====
new_repo
run_ingest "$FIXTURE" --candidate "$CAND" --baseline "$BASE" >/dev/null 2>&1
ci_a=$(record | jq -c '.quality_ci')
new_repo
run_ingest "$FIXTURE" --candidate "$CAND" --baseline "$BASE" >/dev/null 2>&1
ci_b=$(record | jq -c '.quality_ci')
if [ "$ci_a" = "$ci_b" ] && [ "$ci_a" != "null" ]; then
  pass "reproducible: identical quality_ci across two fresh ingests with the same seed ($ci_a)"
else
  fail "CI not reproducible — '$ci_a' vs '$ci_b'"
fi

# ===== 14. Every emitted CI BRACKETS its own point estimate (teeth for the resampler bias) =====
# The LCG low-bit bug produced CIs that excluded their point estimate (e.g. recall_passk=0.833,
# recall_passk_ci=[1,1]). A correct bootstrap can't do that.
new_repo
run_ingest "$FIXTURE" --candidate "$CAND" --baseline "$BASE" >/dev/null 2>&1
rec="$(record)"
qwr=$(printf '%s' "$rec" | jq -r '.quality_winrate_vs_baseline')
qlo=$(printf '%s' "$rec" | jq -r '.quality_ci[0]'); qhi=$(printf '%s' "$rec" | jq -r '.quality_ci[1]')
rpk=$(printf '%s' "$rec" | jq -r '.recall_passk')
rlo=$(printf '%s' "$rec" | jq -r '.recall_passk_ci[0]'); rhi=$(printf '%s' "$rec" | jq -r '.recall_passk_ci[1]')
if fcmp "$qlo <= $qwr && $qwr <= $qhi" && fcmp "$rlo <= $rpk && $rpk <= $rhi"; then
  pass "CIs bracket their point estimates (winrate $qwr in [$qlo,$qhi]; recall^k $rpk in [$rlo,$rhi])"
else
  fail "a CI excludes its point estimate — winrate $qwr in [$qlo,$qhi]? recall^k $rpk in [$rlo,$rhi]?"
fi

# ===== 15. Provenance guard inspects the LINKED eval worktree, not the shared-ledger primary =====
new_linked
LEDGER="$PRIMARY/evals/history.jsonl"   # the shared ledger ingest resolves to from the linked tree
# dirty the LINKED worktree (an uncommitted skill edit) → ingest must refuse even though PRIMARY is clean
echo "uncommitted skill edit" > "$LINKED/skill-edit.txt"
( cd "$LINKED" && bash "$INGEST" "$FIXTURE" --candidate "$CAND" --baseline "$BASE" --bootstrap-reps 800 --seed 7 ) >/dev/null 2>&1
rc=$?
plines_dirty=$(ledger_lines)
rm -f "$LINKED/skill-edit.txt"   # clean the linked tree
( cd "$LINKED" && bash "$INGEST" "$FIXTURE" --candidate "$CAND" --baseline "$BASE" --bootstrap-reps 800 --seed 7 ) >/dev/null 2>&1
rc2=$?
plines_clean=$(ledger_lines)
if [ "$rc" -eq 70 ] && [ "$plines_dirty" -eq 0 ] && [ "$rc2" -eq 0 ] && [ "$plines_clean" -eq 1 ]; then
  pass "linked-worktree guard: dirty linked tree → rc=70 (primary ledger untouched); clean → appends to primary"
else
  fail "linked-worktree provenance wrong — dirty rc=$rc plines=$plines_dirty ; clean rc=$rc2 plines=$plines_clean"
fi

# ===== 16. instructions_digest hashes the loaded files (content digest, not the empty hash) =====
# Catches the bash-3.2 mapfile regression: a present-files dir must yield the sha256 of the
# concatenated sorted contents, NOT the empty-input constant.
new_repo
mkdir -p "$SANDBOX/.geniro/instructions"
printf 'ALPHA' > "$SANDBOX/.geniro/instructions/a-global.md"
printf 'BETA'  > "$SANDBOX/.geniro/instructions/b-style.md"
git -C "$SANDBOX" add .geniro/instructions; git -C "$SANDBOX" commit -q -m "instructions"
expected="sha256:$(cat "$SANDBOX/.geniro/instructions/a-global.md" "$SANDBOX/.geniro/instructions/b-style.md" | shasum -a 256 | awk '{print $1}')"
empty="sha256:$(printf '' | shasum -a 256 | awk '{print $1}')"
run_ingest "$FIXTURE" --candidate "$CAND" --baseline "$BASE" >/dev/null 2>&1
dig=$(record | jq -r '.instructions_digest')
if [ "$dig" = "$expected" ] && [ "$dig" != "$empty" ]; then
  pass "instructions_digest = sha256 of concatenated sorted instruction files (not the empty hash)"
else
  fail "instructions_digest wrong — got '$dig', expected '$expected' (empty would be '$empty')"
fi

# ===== 17. A task missing the required primary_value is rejected (no silent null→0 coercion) =====
new_repo
nopv="$TMPDIR_BASE/bench-nopv.json"
jq 'del(.tasks[1].primary_value)' "$FIXTURE" > "$nopv"
run_ingest "$nopv" --candidate "$CAND" --baseline "$BASE" >/dev/null 2>&1
rc=$?
if [ "$rc" -eq 66 ] && [ "$(ledger_lines)" -eq 0 ]; then
  pass "missing primary_value rejected with rc=66 — not coerced to 0, nothing written"
else
  fail "missing primary_value not rejected with rc=66 — rc=$rc lines=$(ledger_lines)"
fi

# ===== 18. A value-flag with no value (final arg) fails fast, it does NOT hang =====
new_repo
with_timeout 8 bash "$INGEST" "$FIXTURE" --baseline "$BASE" --candidate
rc=$?
if [ "$rc" -eq 64 ]; then
  pass "value-flag missing its value → fast exit 64 (no infinite arg-parse loop)"
else
  fail "valueless trailing flag did not fast-exit 64 — rc=$rc (137 = had to be killed = hang)"
fi

echo
echo "Tests run:    $TESTS_RUN"
echo "Tests failed: $TESTS_FAILED"
[ "$TESTS_FAILED" -eq 0 ]
