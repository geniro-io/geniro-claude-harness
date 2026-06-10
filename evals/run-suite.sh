#!/usr/bin/env bash
# evals/run-suite.sh — the per-run §6 loop, as one reproducible command (plan §6, §16 Phase C).
#
# Drives a geniro skill version-vs-version over a suite and produces a committed ledger row:
#   1. for each suite task × side (candidate, baseline) × trial: run the Phase-0 driver (subscription,
#      gates auto-answered), capturing result.json (tokens/duration) + the produced spec.md;
#   2. GRADE each candidate trial against the task expectations[] with skill-creator's pinned grader.md
#      (evals/vendor/skills) → grading.json;
#   3. POSITION-SWAPPED COMPARE candidate vs baseline per trial with the pinned comparator.md, BOTH
#      orders, averaged → the per-task primary_value (the net-new swap wrapper, plan §10);
#   4. aggregate-runs.sh → benchmark.json;
#   5. (--ingest) ingest.sh → one history.jsonl row + HISTORY.md row.
#
# The honest FIRST run is A-vs-A (same --candidate and --baseline ref): it exercises the whole pipeline
# AND is the empirical-null calibration (plan decision 4) — it must come back a TIE, proving the gate
# does not false-promote on identical inputs. Cost/wall-time are DERIVED by ingest (cache-aware) and
# printed, validating decision 10's estimate (plan §16 Phase C).
#
# Usage:
#   evals/run-suite.sh --skill geniro:plan --suite evals/suites/plan/evals.json \
#     --candidate <sha> --baseline <sha> [--trials 1] [--out <ws>] [--task-ids 1,2] \
#     [--plugin-root <repo>] [--max-turns 300] [--ingest] [--notes "…"] [--dry-run]
#
# --dry-run prints the exact run matrix + commands + a rough cost estimate and spends NOTHING.
# Without --ingest it stops at benchmark.json (inspect, then ingest by hand).
#
# Test seams (so the whole loop runs with fakes, no spend): EVAL_DRIVER_CMD, EVAL_CLAUDE_CMD,
# EVAL_FIXTURE_CMD override the driver / `claude` / target-builder commands.
#
# Exit codes: 0 ok · 64 usage · 65 missing input / no spec produced · (aggregate/ingest rc propagated).
#
# Plugin-developer / eval tooling only — NOT shipped to user projects, NOT loaded by any skill.

set -uo pipefail

_rs_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HARNESS_DIR="$_rs_dir/run-harness"
# Pinned judge prompts live in the evals/vendor/skills submodule. Overridable (EVAL_VENDOR_DIR) so a
# test can point at an empty dir and assert the missing-prompt guard fires (below) instead of the
# silent 0.5 degradation a missing submodule used to cause.
VENDOR="${EVAL_VENDOR_DIR:-$_rs_dir/vendor/skills/skills/skill-creator/agents}"

# Rough per-call cost priors for the dry-run estimate ONLY (the committed cost is derived, not these).
# /plan trial ≈ $2.7 (Phase-0 measured); a grade/compare judging a small spec ≈ $0.15.
EST_DRIVER_USD=2.7
EST_JUDGE_USD=0.15

# Overridable commands. When an EVAL_*_CMD env var is set (tests inject fakes), it is a
# word-split command string; otherwise the default runs the real tool via a QUOTED argv so a
# space in the repo path can't word-split the path itself into a broken invocation.
# Invoke tsx by its ABSOLUTE binary path — NOT `node --import tsx`. The latter resolves the bare
# `tsx` specifier against the process CWD (the worktree root, which has no node_modules) and silently
# ERR_MODULE_NOT_FOUND's; the first live run died this way and scored a vacuous TIE. The .bin/tsx path
# resolves its own deps from its install location, so it works from any CWD.
run_driver()  {
  if [ -n "${EVAL_DRIVER_CMD:-}" ]; then $EVAL_DRIVER_CMD "$@"; return; fi
  local tsx_bin="$HARNESS_DIR/node_modules/.bin/tsx"
  if [ ! -x "$tsx_bin" ]; then
    echo "run-suite: ERROR driver runtime missing — $tsx_bin not found. Run: npm --prefix \"$HARNESS_DIR\" install" >&2
    return 65
  fi
  "$tsx_bin" "$HARNESS_DIR/src/driver.ts" "$@"
}
run_fixture() { if [ -n "${EVAL_FIXTURE_CMD:-}" ]; then $EVAL_FIXTURE_CMD; else bash "$HARNESS_DIR/fixtures/build-plan-fixture.sh"; fi; }
run_claude()  { if [ -n "${EVAL_CLAUDE_CMD:-}" ]; then $EVAL_CLAUDE_CMD "$@"; else claude "$@"; fi; }

# --selfcheck: boot-probe the REAL driver invocation (resolve tsx, load the module, parse args) and
# exit — no suite/candidate needed, no API spend. Guards the run-suite→driver tsx-resolution path that
# silently broke the first live run; a test drives this from a tsx-less CWD (with EVAL_DRIVER_CMD unset).
case " $* " in
  *" --selfcheck "*) run_driver --selfcheck --plugin-raw; exit $? ;;
esac

SKILL="geniro:plan"
# Judge pinned for cross-run comparability (meta.json models_resolved_at marks when this was chosen).
# Passed as --model on every judge call so the recorded judge_model is the model that actually graded —
# without the pin the judge silently runs at the CLI's ambient default while meta.json claims opus.
JUDGE_MODEL="claude-opus-4-8"
SUITE=""
CANDIDATE=""
BASELINE=""
TRIALS=1
OUT=""
TASK_IDS=""
PLUGIN_ROOT=""
MAX_TURNS=300
DO_INGEST=0
DRY_RUN=0
NOTES=""

_need_val() { [ "$1" -ge 2 ] || { echo "run-suite: $2 requires a value" >&2; exit 64; }; }
while [ $# -gt 0 ]; do
  case "$1" in
    --skill) _need_val "$#" "$1"; SKILL="$2"; shift 2;;
    --suite) _need_val "$#" "$1"; SUITE="$2"; shift 2;;
    --candidate) _need_val "$#" "$1"; CANDIDATE="$2"; shift 2;;
    --baseline) _need_val "$#" "$1"; BASELINE="$2"; shift 2;;
    --trials) _need_val "$#" "$1"; TRIALS="$2"; shift 2;;
    --out) _need_val "$#" "$1"; OUT="$2"; shift 2;;
    --task-ids) _need_val "$#" "$1"; TASK_IDS="$2"; shift 2;;
    --plugin-root) _need_val "$#" "$1"; PLUGIN_ROOT="$2"; shift 2;;
    --max-turns) _need_val "$#" "$1"; MAX_TURNS="$2"; shift 2;;
    --notes) _need_val "$#" "$1"; NOTES="$2"; shift 2;;
    --ingest) DO_INGEST=1; shift;;
    --dry-run) DRY_RUN=1; shift;;
    -h|--help) sed -n '20,33p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0;;
    --*) echo "run-suite: unknown flag $1" >&2; exit 64;;
    *) echo "run-suite: unexpected argument $1" >&2; exit 64;;
  esac
done

[ -n "$SUITE" ] || { echo "run-suite: --suite <evals.json> is required" >&2; exit 64; }
[ -f "$SUITE" ] || { echo "run-suite: suite not found: $SUITE" >&2; exit 65; }
if ! jq -e '.evals' "$SUITE" >/dev/null 2>&1; then
  echo "run-suite: suite is not a skill-creator evals.json (missing .evals): $SUITE" >&2; exit 65
fi
[ -n "$CANDIDATE" ] || { echo "run-suite: --candidate <ref> is required" >&2; exit 64; }
[ -n "$BASELINE" ]  || { echo "run-suite: --baseline <ref> is required" >&2; exit 64; }
case "$TRIALS" in (*[!0-9]*|'') echo "run-suite: --trials must be a positive integer" >&2; exit 64;; esac
[ "$TRIALS" -ge 1 ] || { echo "run-suite: --trials must be >= 1" >&2; exit 64; }

PLUGIN_ROOT="${PLUGIN_ROOT:-$(cd "$_rs_dir/.." && pwd)}"
# holdout_partition: the suite filename signals which partition gates promotion (plan §11).
case "$SUITE" in (*holdout*) HOLDOUT=true;; (*) HOLDOUT=false;; esac
SKILL_SHORT="${SKILL#*:}"   # geniro:plan → plan (the ledger `skill`)

# Which task ids to run (default: all in the suite).
if [ -n "$TASK_IDS" ]; then
  IDS="$(printf '%s' "$TASK_IDS" | tr ',' ' ')"
else
  IDS="$(jq -r '.evals[].id' "$SUITE" | tr '\n' ' ')"
fi
NTASKS=0; for _ in $IDS; do NTASKS=$((NTASKS+1)); done

WORKSPACE="${OUT:-$_rs_dir/runs/suite-$SKILL_SHORT-$(jq -rn 'now|todate' 2>/dev/null | tr ':' '-' || echo manual)}"

n_driver=$(( NTASKS * 2 * TRIALS ))
n_grade=$(( NTASKS * TRIALS ))
n_compare=$(( NTASKS * TRIALS * 2 ))
est_total="$(awk -v d="$n_driver" -v g="$n_grade" -v c="$n_compare" -v du="$EST_DRIVER_USD" -v ju="$EST_JUDGE_USD" \
  'BEGIN{ printf "%.0f", d*du + (g+c)*ju }')"

echo "run-suite: skill=$SKILL  suite=$SUITE  partition=$([ "$HOLDOUT" = true ] && echo held-out || echo dev)"
echo "run-suite: candidate=$CANDIDATE  baseline=$BASELINE  $([ "$CANDIDATE" = "$BASELINE" ] && echo '(A-vs-A null calibration → expect a TIE)')"
echo "run-suite: tasks=$NTASKS [$IDS] × trials=$TRIALS × 2 sides = $n_driver driver runs; $n_grade grades; $n_compare comparisons"
echo "run-suite: rough cost estimate ≈ \$$est_total (driver ${n_driver}×\$$EST_DRIVER_USD + judge $((n_grade+n_compare))×\$$EST_JUDGE_USD) — committed cost is DERIVED cache-aware, not this"
echo "run-suite: workspace = $WORKSPACE"

# meta.json (provenance carried into benchmark.json by aggregate-runs.sh).
write_meta() {
  mkdir -p "$WORKSPACE"
  jq -n --arg skill "$SKILL_SHORT" --arg cand "$CANDIDATE" --arg base "$BASELINE" \
    --arg jm "$JUDGE_MODEL" \
    --argjson holdout "$HOLDOUT" '{
      schema_version:"benchmark-v1", skill:$skill, candidate_ref:$cand, baseline_ref:$base,
      executor_model:null, judge_model:$jm, judge_temperature:0.0, executor_temperature:1.0,
      models_resolved_at:"2026-06-06", auq_autoanswer_policy:"approve-default-v1",
      holdout_partition:$holdout, position_swapped:true,
      primary_metric:"quality_winrate_vs_baseline", primary_null:0.5
    } | with_entries(select(.value != null))' > "$WORKSPACE/meta.json"
}

if [ "$DRY_RUN" -eq 1 ]; then
  echo
  echo "run-suite: DRY RUN — no skill runs, no judge calls, nothing spent. Per task it would:"
  for id in $IDS; do
    p="$(jq -r --argjson i "$id" '.evals[] | select(.id == $i) | .prompt' "$SUITE" 2>/dev/null \
        || jq -r --arg i "$id" '.evals[] | select((.id|tostring) == $i) | .prompt' "$SUITE")"
    echo "  • eval-$id: drive ${TRIALS}× candidate@$CANDIDATE + ${TRIALS}× baseline@$BASELINE, grade candidate, swap-compare → primary_value"
    echo "      prompt: ${p:0:96}"
  done
  echo "  then: aggregate-runs.sh \"$WORKSPACE\" --out \"$WORKSPACE/benchmark.json\""
  [ "$DO_INGEST" -eq 1 ] && echo "  then: ingest.sh \"$WORKSPACE/benchmark.json\" --candidate $CANDIDATE --baseline $BASELINE"
  exit 0
fi

write_meta

# Read a pinned judge agent prompt (grader.md / comparator.md) from the submodule.
agent_prompt() { cat "$VENDOR/$1" 2>/dev/null || { echo "run-suite: pinned $1 not found under $VENDOR (submodule checked out?)" >&2; exit 65; }; }

# Call `claude -p` headlessly and return exactly the FIRST JSON object the model emitted.
# A judge often appends prose after its JSON even when told "JSON only" — slurping to EOF and
# feeding that to jq would make jq exit nonzero (then a `|| echo TIE`-style fallback would
# corrupt the value). So: strip ```fences, cut from the first `{` CHARACTER (handles same-line
# preamble), then `jq first(inputs)` returns the first object and LAZILY ignores trailing prose.
claude_json() {
  local prompt="$1" raw
  raw="$(run_claude -p "$prompt" --model "$JUDGE_MODEL" --output-format json 2>/dev/null | jq -r '.result // empty' 2>/dev/null)"
  [ -n "$raw" ] || raw="$(run_claude -p "$prompt" --model "$JUDGE_MODEL" 2>/dev/null)"     # fallback: plain text
  printf '%s' "$raw" | tr -d '\r' | sed -e 's/^```json//' -e 's/^```//' -e 's/```$//' \
    | awk 'f{print;next}{i=index($0,"{");if(i>0){print substr($0,i);f=1}}' \
    | jq -cn 'first(inputs)' 2>/dev/null
}

# Grade one candidate trial's spec against the task expectations → write grading.json.
grade_trial() {
  local spec="$1" prompt="$2" exps="$3" out="$4"
  if [ ! -f "$spec" ]; then echo "run-suite: no spec to grade at $spec" >&2; return 1; fi
  local g full; g="$(agent_prompt grader.md)"
  full="$g

## Eval task
$prompt

## Expectations (grade each PASS/FAIL)
$exps

## Output under evaluation (spec.md)
$(cat "$spec")

Return ONLY the grading JSON object described above (expectations[] with passed booleans + summary). No prose."
  local j; j="$(claude_json "$full")"
  if printf '%s' "$j" | jq -e '.expectations' >/dev/null 2>&1; then printf '%s\n' "$j" | jq . > "$out"; else
    echo "run-suite: grader did not return valid grading JSON for $spec" >&2; return 1; fi
}

# Comparator on one ordered pair; echoes a NORMALISED winner label — exactly "A", "B", or "TIE".
# Uppercase-fold (a lowercase 'a'/'b' verdict is a contract violation, not a tie) + allowlist so any
# off-contract value collapses to TIE deterministically (not via a fragile pipe-exit fallback).
compare_once() {
  local a="$1" b="$2" prompt="$3" exps="$4"
  local c full w; c="$(agent_prompt comparator.md)"
  full="$c

## Eval task
$prompt

## Expectations (optional secondary signal)
$exps

## Output A
$(cat "$a")

## Output B
$(cat "$b")

Return ONLY the comparison JSON object described above (with a top-level \"winner\" of \"A\", \"B\", or \"TIE\"). No prose."
  w="$(claude_json "$full" | jq -r '.winner // empty' 2>/dev/null | head -1 | tr '[:lower:]' '[:upper:]')"
  case "$w" in A|B|TIE) printf '%s' "$w";; *) printf 'TIE';; esac
}

# Position-swapped comparison of one trial pair → candidate-win fraction in {0, 0.5, 1}.
# Average in jq (locale-stable, always dot-decimal) — an awk `printf "%g"` honours LC_NUMERIC and
# would emit a comma-decimal under e.g. de_DE, which the downstream `jq --argjson` then rejects.
compare_swapped() {
  local cand="$1" base="$2" prompt="$3" exps="$4"
  local w1 w2 s1 s2
  w1="$(compare_once "$cand" "$base" "$prompt" "$exps")"   # A=candidate
  w2="$(compare_once "$base" "$cand" "$prompt" "$exps")"   # A=baseline (swapped)
  case "$w1" in (A) s1=1;; (B) s1=0;; (*) s1=0.5;; esac     # cand is A
  case "$w2" in (B) s2=1;; (A) s2=0;; (*) s2=0.5;; esac     # cand is B
  jq -n --argjson a "$s1" --argjson b "$s2" '($a + $b) / 2'
}

locate_spec() { find "$1/.geniro/planning" -name 'spec.md' -type f 2>/dev/null | LC_ALL=C sort | head -1; }

# Pre-flight: the pinned judge prompts MUST exist before we spend anything. Otherwise agent_prompt's
# `exit 65` (swallowed inside command substitution) leaves an empty template, the comparator builds a
# headerless prompt, and EVERY comparison silently collapses to a no-winner TIE (primary_value 0.5) —
# a misconfiguration masquerading as a real result. Fail loud here in the main shell so it propagates.
for _pp in grader.md comparator.md; do
  if [ ! -f "$VENDOR/$_pp" ]; then
    echo "run-suite: pinned judge prompt $_pp not found under $VENDOR — run: git submodule update --init evals/vendor/skills" >&2
    exit 65
  fi
done

for id in $IDS; do
  prompt="$(jq -r --argjson i "$id" '.evals[] | select(.id == $i) | .prompt' "$SUITE" 2>/dev/null)"
  [ -n "$prompt" ] || prompt="$(jq -r --arg i "$id" '.evals[] | select((.id|tostring) == $i) | .prompt' "$SUITE")"
  exps="$(jq -c --argjson i "$id" '.evals[] | select(.id == $i) | .expectations' "$SUITE" 2>/dev/null)"
  [ -n "$exps" ] && [ "$exps" != "null" ] || exps="$(jq -c --arg i "$id" '.evals[] | select((.id|tostring) == $i) | .expectations' "$SUITE")"
  if [ -z "$prompt" ] || [ "$prompt" = "null" ]; then echo "run-suite: task id $id not found in $SUITE" >&2; exit 65; fi
  echo "run-suite: ── eval-$id ──"

  i=1
  while [ "$i" -le "$TRIALS" ]; do
    for side in candidate baseline; do
      ref="$CANDIDATE"; [ "$side" = baseline ] && ref="$BASELINE"
      target="$(run_fixture | tail -1)"
      outdir="$WORKSPACE/eval-$id/$side/run-$i"; mkdir -p "$outdir"
      echo "run-suite:   drive $side trial $i (ref=$ref, target=$target)"
      run_driver --skill "$SKILL" --plugin-root "$PLUGIN_ROOT" --plugin-ref "$ref" \
        --cwd "$target" --out "$outdir" --max-turns "$MAX_TURNS" --prompt "$prompt" || \
        echo "run-suite:   WARN driver returned non-zero for $side trial $i (incomplete run will grade low)" >&2
      spec="$(locate_spec "$target")"
      if [ -n "$spec" ]; then cp "$spec" "$outdir/spec.md"; else echo "run-suite:   WARN no spec.md produced for $side trial $i" >&2; fi
    done
    i=$((i+1))
  done

  # grade candidate trials (expectation_pass / pass_rate is the candidate side)
  i=1
  while [ "$i" -le "$TRIALS" ]; do
    grade_trial "$WORKSPACE/eval-$id/candidate/run-$i/spec.md" "$prompt" "$exps" \
      "$WORKSPACE/eval-$id/candidate/run-$i/grading.json" || true
    i=$((i+1))
  done

  # position-swapped comparison per trial → mean candidate-win = primary_value
  wins="[]"
  i=1
  while [ "$i" -le "$TRIALS" ]; do
    cspec="$WORKSPACE/eval-$id/candidate/run-$i/spec.md"
    bspec="$WORKSPACE/eval-$id/baseline/run-$i/spec.md"
    if [ -f "$cspec" ] && [ -f "$bspec" ]; then
      w="$(compare_swapped "$cspec" "$bspec" "$prompt" "$exps")"
      wins="$(jq -c --argjson w "$w" '. + [$w]' <<<"$wins")"
    fi
    i=$((i+1))
  done
  pv="$(jq -n --argjson w "$wins" 'if ($w|length)>0 then ($w|add/length) else 0.5 end')"
  jq -n --argjson pv "$pv" '{primary_value:$pv}' > "$WORKSPACE/eval-$id/comparison.json"
  echo "run-suite:   eval-$id primary_value=$pv (candidate-win fraction over $TRIALS swapped trials)"
done

echo "run-suite: aggregating → $WORKSPACE/benchmark.json"
bash "$_rs_dir/aggregate-runs.sh" "$WORKSPACE" --out "$WORKSPACE/benchmark.json"
arc=$?
if [ "$arc" -ne 0 ]; then echo "run-suite: aggregate-runs failed (rc=$arc)" >&2; exit "$arc"; fi

if [ "$DO_INGEST" -eq 1 ]; then
  echo "run-suite: ingesting → ledger"
  bash "$_rs_dir/ingest.sh" "$WORKSPACE/benchmark.json" --candidate "$CANDIDATE" --baseline "$BASELINE" \
    ${NOTES:+--notes "$NOTES"}
  irc=$?
  [ "$irc" -eq 0 ] || { echo "run-suite: ingest failed (rc=$irc)" >&2; exit "$irc"; }
else
  echo "run-suite: benchmark.json ready — inspect it, then: bash evals/ingest.sh \"$WORKSPACE/benchmark.json\" --candidate $CANDIDATE --baseline $BASELINE"
fi
