#!/usr/bin/env bash
# Integration tests for evals/aggregate-runs.sh — the Phase-C glue (plan §16; BENCHMARK-SCHEMA.md).
#
# Run: bash tests/evals/aggregate-runs.sh   (auto-discovered by tests/run-all.sh)
# Exits non-zero on any failure.
#
# Plugin-developer / eval tooling only — not shipped to user projects.
#
# Contract under test: aggregate-runs maps a harness benchmark WORKSPACE (per-trial result.json +
# grading.json, plus a position-swapped comparison.json per task, plus meta.json) into one
# benchmark.json conforming to BENCHMARK-SCHEMA.md:
#   - token usage is summed per side across trials, read from .model_usage (authoritative) with a
#     .usage fallback, preserving cache tiers (a geniro run is cache-read-dominated)
#   - expectation_pass is the CANDIDATE side's per-trial 0/1 over the suite expectations[]
#   - primary_value is REQUIRED per task (a task without it is a hard error — ingest would reject it)
#   - the assembled benchmark.json flows through ingest.sh to a sane ledger row (A-vs-A → a TIE)

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
AGG="$REPO_ROOT/evals/aggregate-runs.sh"
INGEST="$REPO_ROOT/evals/ingest.sh"

TMPDIR_BASE="$(cd "$(mktemp -d)" && pwd -P)"
ORIGINAL_PWD="$PWD"
trap 'cd "$ORIGINAL_PWD"; rm -rf "$TMPDIR_BASE"' EXIT

TESTS_RUN=0
TESTS_FAILED=0
pass() { TESTS_RUN=$((TESTS_RUN + 1)); echo "PASS: $1"; }
fail() { TESTS_RUN=$((TESTS_RUN + 1)); TESTS_FAILED=$((TESTS_FAILED + 1)); echo "FAIL: $1" >&2; }
fcmp() { awk "BEGIN{ exit !($1) }"; }

# Write a harness result.json (model_usage form) at <dir>/result.json.
# args: dir model inTok outTok cacheRead cacheCreate durationMs
mk_result_mu() {
  mkdir -p "$1"
  jq -n --arg m "$2" --argjson i "$3" --argjson o "$4" --argjson cr "$5" --argjson cc "$6" --argjson d "$7" \
    '{completed:true, duration_ms:$d, total_cost_usd:0,
      model_usage: { ($m): { inputTokens:$i, outputTokens:$o, cacheReadInputTokens:$cr, cacheCreationInputTokens:$cc, costUSD:0 } },
      usage: null }' > "$1/result.json"
}
# Write a result.json with ONLY the .usage (snake_case) form — model_usage absent (fallback path).
mk_result_usage() {
  mkdir -p "$1"
  jq -n --argjson i "$2" --argjson o "$3" --argjson cr "$4" --argjson cc "$5" --argjson d "$6" \
    '{completed:true, duration_ms:$d,
      usage: { input_tokens:$i, output_tokens:$o, cache_read_input_tokens:$cr, cache_creation_input_tokens:$cc } }' > "$1/result.json"
}
# Write a grading.json with the given pass booleans (1/0 args) at <dir>/grading.json.
mk_grading() {
  local dir="$1"; shift
  mkdir -p "$dir"
  local arr="[]"
  local i=0
  for p in "$@"; do
    arr="$(jq -c --argjson p "$p" --argjson n "$i" '. + [{text:("exp"+($n|tostring)), passed:($p==1)}]' <<<"$arr")"
    i=$((i+1))
  done
  jq -n --argjson e "$arr" '{expectations:$e, summary:{passed:($e|map(select(.passed))|length), total:($e|length), pass_rate:0}}' > "$dir/grading.json"
}
# meta.json with sane A-vs-A defaults; extra jq filter in $2 can tweak it.
mk_meta() {
  local ws="$1" filter="${2:-.}"
  jq -n '{
    schema_version:"benchmark-v1", skill:"plan",
    candidate_ref:"CAND", baseline_ref:"BASE",
    executor_model:"claude-opus-4-8", judge_model:"claude-opus-4-8",
    models_resolved_at:"2026-06-06", executor_temperature:1.0, judge_temperature:0.0,
    auq_autoanswer_policy:"approve-default-v1", holdout_partition:false, position_swapped:true,
    primary_metric:"quality_winrate_vs_baseline", primary_null:0.5
  }' | jq "$filter" > "$ws/meta.json"
}

# ===== 1. Basic 2-task workspace: tokens summed, schema shape, primary_value carried =====
WS="$TMPDIR_BASE/ws1"; mkdir -p "$WS"; mk_meta "$WS"
for t in 1 2; do
  mk_result_mu  "$WS/eval-$t/candidate/run-1" claude-opus-4-8 1000 500 9000 200 30000
  mk_grading    "$WS/eval-$t/candidate/run-1" 1 1 0
  mk_result_mu  "$WS/eval-$t/baseline/run-1"  claude-opus-4-8 1100 520 9100 210 31000
  mk_grading    "$WS/eval-$t/baseline/run-1"  1 1 1
  jq -n '{primary_value:0.5}' > "$WS/eval-$t/comparison.json"
done
bench="$($AGG "$WS" 2>/dev/null)"; rc=$?
ntasks=$(jq '.tasks|length' <<<"$bench")
cin=$(jq '.tasks[0].candidate.input_tokens' <<<"$bench")
cout=$(jq '.tasks[0].candidate.output_tokens' <<<"$bench")
ccr=$(jq '.tasks[0].candidate.cache_read_tokens' <<<"$bench")
pv=$(jq '.tasks[0].primary_value' <<<"$bench")
epl=$(jq '.tasks[0].expectation_pass|length' <<<"$bench")
if [ "$rc" -eq 0 ] && [ "$ntasks" = "2" ] && [ "$cin" = "1000" ] && [ "$cout" = "500" ] \
   && [ "$ccr" = "9000" ] && [ "$pv" = "0.5" ] && [ "$epl" = "3" ]; then
  pass "basic: 2 tasks, candidate tokens {in:1000,out:500,cache_read:9000}, primary_value=0.5, expectation_pass len 3"
else
  fail "basic shape wrong — rc=$rc ntasks=$ntasks cin=$cin cout=$cout ccr=$ccr pv=$pv epl=$epl"
fi

# ===== 2. Multi-trial pooling: tokens summed across trials, expectation_pass length = trials×exps =====
WS="$TMPDIR_BASE/ws2"; mkdir -p "$WS"; mk_meta "$WS"
mk_result_mu "$WS/eval-1/candidate/run-1" claude-opus-4-8 1000 500 9000 200 30000
mk_result_mu "$WS/eval-1/candidate/run-2" claude-opus-4-8 2000 700 9500 300 32000
mk_grading   "$WS/eval-1/candidate/run-1" 1 0
mk_grading   "$WS/eval-1/candidate/run-2" 1 1
mk_result_mu "$WS/eval-1/baseline/run-1" claude-opus-4-8 1000 500 9000 200 30000
mk_result_mu "$WS/eval-1/baseline/run-2" claude-opus-4-8 2000 700 9500 300 32000
mk_grading   "$WS/eval-1/baseline/run-1" 1 1
mk_grading   "$WS/eval-1/baseline/run-2" 1 1
jq -n '{primary_value:0.5}' > "$WS/eval-1/comparison.json"
bench="$($AGG "$WS" 2>/dev/null)"
cin=$(jq '.tasks[0].candidate.input_tokens' <<<"$bench")     # 1000+2000
cout=$(jq '.tasks[0].candidate.output_tokens' <<<"$bench")   # 500+700
trials=$(jq '.tasks[0].trials' <<<"$bench")
epl=$(jq '.tasks[0].expectation_pass|length' <<<"$bench")    # 2 trials × 2 exps
epsum=$(jq '.tasks[0].expectation_pass|add' <<<"$bench")     # 1+0+1+1
if [ "$cin" = "3000" ] && [ "$cout" = "1200" ] && [ "$trials" = "2" ] && [ "$epl" = "4" ] && [ "$epsum" = "3" ]; then
  pass "multi-trial: tokens summed over trials (in=3000 out=1200), trials=2, expectation_pass len 4 sum 3"
else
  fail "multi-trial pooling wrong — cin=$cin cout=$cout trials=$trials epl=$epl epsum=$epsum"
fi

# ===== 3. .usage fallback when model_usage is absent =====
WS="$TMPDIR_BASE/ws3"; mkdir -p "$WS"; mk_meta "$WS"
mk_result_usage "$WS/eval-1/candidate/run-1" 1234 567 8888 111 30000
mk_grading      "$WS/eval-1/candidate/run-1" 1 1
mk_result_usage "$WS/eval-1/baseline/run-1"  1234 567 8888 111 30000
mk_grading      "$WS/eval-1/baseline/run-1"  1 1
jq -n '{primary_value:0.5}' > "$WS/eval-1/comparison.json"
bench="$($AGG "$WS" --skill plan 2>/dev/null)"
cin=$(jq '.tasks[0].candidate.input_tokens' <<<"$bench")
ccr=$(jq '.tasks[0].candidate.cache_read_tokens' <<<"$bench")
if [ "$cin" = "1234" ] && [ "$ccr" = "8888" ]; then
  pass ".usage fallback: tokens read from .usage when model_usage absent (in=1234 cache_read=8888)"
else
  fail ".usage fallback wrong — cin=$cin ccr=$ccr"
fi

# ===== 4. A task missing comparison.json/primary_value is a HARD error (rc 66) =====
WS="$TMPDIR_BASE/ws4"; mkdir -p "$WS"; mk_meta "$WS"
mk_result_mu "$WS/eval-1/candidate/run-1" claude-opus-4-8 1000 500 9000 200 30000
mk_grading   "$WS/eval-1/candidate/run-1" 1 1
mk_result_mu "$WS/eval-1/baseline/run-1"  claude-opus-4-8 1000 500 9000 200 30000
mk_grading   "$WS/eval-1/baseline/run-1"  1 1
# no comparison.json
$AGG "$WS" >/dev/null 2>&1; rc=$?
WS2="$TMPDIR_BASE/ws4b"; mkdir -p "$WS2"; mk_meta "$WS2"
mk_result_mu "$WS2/eval-1/candidate/run-1" claude-opus-4-8 1000 500 9000 200 30000
mk_grading   "$WS2/eval-1/candidate/run-1" 1 1
mk_result_mu "$WS2/eval-1/baseline/run-1"  claude-opus-4-8 1000 500 9000 200 30000
mk_grading   "$WS2/eval-1/baseline/run-1"  1 1
jq -n '{primary_value:null}' > "$WS2/eval-1/comparison.json"   # present but null
$AGG "$WS2" >/dev/null 2>&1; rc2=$?
if [ "$rc" -eq 66 ] && [ "$rc2" -eq 66 ]; then
  pass "missing/null primary_value → hard error rc=66 (no benchmark with an ungradeable task)"
else
  fail "missing primary_value not rejected rc=66 — absent=$rc null=$rc2"
fi

# ===== 5. length_confounded heuristic: candidate output ≫ baseline → true; equal → false =====
WS="$TMPDIR_BASE/ws5"; mkdir -p "$WS"; mk_meta "$WS"
mk_result_mu "$WS/eval-1/candidate/run-1" claude-opus-4-8 1000 5000 9000 200 30000   # 5000 out
mk_grading   "$WS/eval-1/candidate/run-1" 1 1
mk_result_mu "$WS/eval-1/baseline/run-1"  claude-opus-4-8 1000 1000 9000 200 30000   # 1000 out  → 5x
mk_grading   "$WS/eval-1/baseline/run-1"  1 1
jq -n '{primary_value:0.6}' > "$WS/eval-1/comparison.json"
lc=$(jq -r '.length_confounded' <<<"$($AGG "$WS" 2>/dev/null)")
WS="$TMPDIR_BASE/ws5b"; mkdir -p "$WS"; mk_meta "$WS"
mk_result_mu "$WS/eval-1/candidate/run-1" claude-opus-4-8 1000 1000 9000 200 30000
mk_grading   "$WS/eval-1/candidate/run-1" 1 1
mk_result_mu "$WS/eval-1/baseline/run-1"  claude-opus-4-8 1000 1000 9000 200 30000
mk_grading   "$WS/eval-1/baseline/run-1"  1 1
jq -n '{primary_value:0.5}' > "$WS/eval-1/comparison.json"
lc_eq=$(jq -r '.length_confounded' <<<"$($AGG "$WS" 2>/dev/null)")
if [ "$lc" = "true" ] && [ "$lc_eq" = "false" ]; then
  pass "length_confounded: 5x output divergence → true; equal output → false"
else
  fail "length_confounded heuristic wrong — divergent=$lc equal=$lc_eq"
fi

# ===== 6. executor_model inferred from model_usage key when meta omits it =====
WS="$TMPDIR_BASE/ws6"; mkdir -p "$WS"; mk_meta "$WS" 'del(.executor_model)'
mk_result_mu "$WS/eval-1/candidate/run-1" "claude-opus-4-8[1m]" 1000 500 9000 200 30000
mk_grading   "$WS/eval-1/candidate/run-1" 1 1
mk_result_mu "$WS/eval-1/baseline/run-1"  "claude-opus-4-8[1m]" 1000 500 9000 200 30000
mk_grading   "$WS/eval-1/baseline/run-1"  1 1
jq -n '{primary_value:0.5}' > "$WS/eval-1/comparison.json"
em=$(jq -r '.executor_model' <<<"$($AGG "$WS" 2>/dev/null)")
if [ "$em" = "claude-opus-4-8[1m]" ]; then
  pass "executor_model inferred from model_usage key when meta omits it (claude-opus-4-8[1m])"
else
  fail "executor_model inference wrong — got '$em'"
fi

# ===== 7. END-TO-END: aggregate → ingest → a ledger row; A-vs-A is a TIE; [1m] alias priced =====
# Uses the REAL plan-ec1 model_usage token shape (10100/34374/2173960/110797) keyed by the 1M-context
# id claude-opus-4-8[1m], with meta omitting executor_model so it is INFERRED. This pins three things:
#  (a) the [1m] price-map alias is exercised end-to-end (a dropped alias → ingest rc 72 → this test RED);
#  (b) cache-aware cost reproduces the SDK costUSD $2.6893 to the cent (band 2.68–2.70, teeth on a cache-tier slip);
#  (c) A-vs-A is a committed TIE with cost_delta 0.
SB="$(mktemp -d "$TMPDIR_BASE/sb.XXXX")"
git -C "$SB" init -q; git -C "$SB" config user.email e@e.l; git -C "$SB" config user.name e
git -C "$SB" commit --allow-empty -q -m base; REF="$(git -C "$SB" rev-parse HEAD)"
mkdir -p "$SB/evals"; : > "$SB/evals/history.jsonl"; git -C "$SB" add evals/history.jsonl; git -C "$SB" commit -q -m seed
WS="$TMPDIR_BASE/ws7"; mkdir -p "$WS"; mk_meta "$WS" 'del(.executor_model)'
for t in 1 2 3; do
  for s in candidate baseline; do
    mk_result_mu "$WS/eval-$t/$s/run-1" "claude-opus-4-8[1m]" 10100 34374 2173960 110797 450000
    mk_grading   "$WS/eval-$t/$s/run-1" 1 1 1
  done
  jq -n '{primary_value:0.5}' > "$WS/eval-$t/comparison.json"   # A-vs-A: no side wins
done
benchfile="$TMPDIR_BASE/bench7.json"
$AGG "$WS" --out "$benchfile" 2>/dev/null
em7=$(jq -r '.executor_model' "$benchfile" 2>/dev/null)
( cd "$SB" && bash "$INGEST" "$benchfile" --candidate "$REF" --baseline "$REF" --bootstrap-reps 1500 --seed 5 ) >/dev/null 2>&1
irc=$?
row="$(tail -n1 "$SB/evals/history.jsonl" 2>/dev/null)"
sig=$(printf '%s' "$row" | jq -r '.significant_on_primary')
beats=$(printf '%s' "$row" | jq -r '.primary_beats_null')
cost=$(printf '%s' "$row" | jq -r '.mean_cost_usd')
cdelta=$(printf '%s' "$row" | jq -r '.cost_delta')
if [ "$irc" -eq 0 ] && [ "$em7" = "claude-opus-4-8[1m]" ] && [ "$sig" = "false" ] && [ "$beats" = "false" ] \
   && fcmp "$cost > 2.68 && $cost < 2.70" && [ "$cdelta" = "0" ]; then
  pass "end-to-end (real model_usage shape, [1m] alias priced): A-vs-A TIE, cache-aware cost=\$$cost (≈SDK \$2.6893), cost_delta=0"
else
  fail "end-to-end chain wrong — irc=$irc execmodel=$em7 sig=$sig beats=$beats cost=$cost (want 2.68–2.70) cost_delta=$cdelta"
fi

# ===== 8. --out writes a file; numeric task id stays numeric; cache fields present per side =====
WS="$TMPDIR_BASE/ws8"; mkdir -p "$WS"; mk_meta "$WS"
mk_result_mu "$WS/eval-7/candidate/run-1" claude-opus-4-8 1000 500 9000 200 30000
mk_grading   "$WS/eval-7/candidate/run-1" 1 1
mk_result_mu "$WS/eval-7/baseline/run-1"  claude-opus-4-8 1000 500 9000 200 30000
mk_grading   "$WS/eval-7/baseline/run-1"  1 1
jq -n '{primary_value:0.5}' > "$WS/eval-7/comparison.json"
of="$TMPDIR_BASE/out8.json"
$AGG "$WS" --out "$of" 2>/dev/null
idtype=$(jq -r '.tasks[0].id | type' "$of" 2>/dev/null)
idval=$(jq -r '.tasks[0].id' "$of" 2>/dev/null)
cc=$(jq -r '.tasks[0].candidate.cache_creation_tokens' "$of" 2>/dev/null)
if [ -f "$of" ] && [ "$idtype" = "number" ] && [ "$idval" = "7" ] && [ "$cc" = "200" ]; then
  pass "--out writes file; numeric id 7 stays a number; cache_creation_tokens preserved (200)"
else
  fail "--out / id / cache wrong — file? idtype=$idtype idval=$idval cc=$cc"
fi

echo
echo "Tests run:    $TESTS_RUN"
echo "Tests failed: $TESTS_FAILED"
[ "$TESTS_FAILED" -eq 0 ]
