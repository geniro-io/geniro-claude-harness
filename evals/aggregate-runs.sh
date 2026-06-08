#!/usr/bin/env bash
# evals/aggregate-runs.sh — the Phase-C glue (plan §16, Phase C; BENCHMARK-SCHEMA.md "Phase-C wiring").
#
# Maps a harness BENCHMARK WORKSPACE (the per-trial run dirs + grader/comparator outputs) into one
# benchmark.json conforming to evals/BENCHMARK-SCHEMA.md, which evals/ingest.sh then turns into a
# committed ledger row. It is the boundary between the RUN side (Phase-0 driver + skill-creator's
# grader.md/comparator.md, pinned in evals/vendor/skills) and the BOOKKEEPING side (ingest).
#
# Why this and not skill-creator's aggregate_benchmark.py: that script pre-aggregates grading.json
# into per-config mean/stddev and carries NO comparator winrate and NO SDK token usage (it reads a
# sibling timing.json). ingest needs the RAW per-task structure (the task is the unit of randomization
# — plan decision 4), the position-swapped winrate as primary_value, and the harness result.json token
# usage. So this glue reads the SAME grading.json aggregate_benchmark.py consumes, plus the harness
# result.json and the position-swap comparison.json, and assembles the per-task schema directly.
#
# Workspace layout (produced by evals/run-suite.sh):
#   <workspace>/
#     meta.json                              run config / provenance (skill, refs, models, temps, policy)
#     eval-<id>/
#       candidate/run-<i>/result.json        harness summary (.model_usage|.usage, .duration_ms)
#       candidate/run-<i>/grading.json       grader output (.expectations[].passed)
#       baseline/run-<i>/result.json
#       baseline/run-<i>/grading.json
#       comparison.json                      {primary_value, recall_passk?, recall_at1?,
#                                             precision_hits?, precision_total?}  ← position-swapped
#
# Token usage is read from .model_usage (the authoritative cumulative; its costUSD matches
# total_cost_usd) and falls back to .usage; cache tiers are preserved so ingest prices them correctly
# (a geniro run is cache-read-dominated). expectation_pass is the CANDIDATE side's per-trial 0/1 over
# the suite expectations[] (the version under evaluation; → pass_rate). primary_value is REQUIRED per
# task — a task without it is a hard error (ingest would reject the whole run otherwise).
#
# Usage:
#   evals/aggregate-runs.sh <workspace> [--out <benchmark.json>] \
#     [--skill <name>] [--candidate <sha>] [--baseline <sha>] [--length-confound-threshold <f>]
# Flags override the matching meta.json field. Writes to --out, else stdout.
#
# Exit codes: 0 ok · 64 usage · 65 malformed/missing workspace input · 66 a task is missing primary_value.
#
# Plugin-developer / eval tooling only — NOT shipped to user projects, NOT loaded by any skill.

set -uo pipefail

# Output-token ratio outside [1/(1+t), 1+t] flags a length/format confound (plan §10): the winrate
# gate alone may not clear, the pointwise anchor + reference recall must corroborate. meta.json may
# override with an explicit length_confounded. 0.25 = a 25% mean-output-length divergence.
LEN_CONFOUND_THRESHOLD=0.25

WS=""
OUT=""
SKILL_OVERRIDE=""
CAND_OVERRIDE=""
BASE_OVERRIDE=""

_need_val() { [ "$1" -ge 2 ] || { echo "aggregate-runs: $2 requires a value" >&2; exit 64; }; }

while [ $# -gt 0 ]; do
  case "$1" in
    --out) _need_val "$#" "$1"; OUT="$2"; shift 2;;
    --skill) _need_val "$#" "$1"; SKILL_OVERRIDE="$2"; shift 2;;
    --candidate) _need_val "$#" "$1"; CAND_OVERRIDE="$2"; shift 2;;
    --baseline) _need_val "$#" "$1"; BASE_OVERRIDE="$2"; shift 2;;
    --length-confound-threshold) _need_val "$#" "$1"; LEN_CONFOUND_THRESHOLD="$2"; shift 2;;
    -h|--help) sed -n '32,40p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0;;
    --*) echo "aggregate-runs: unknown flag $1" >&2; exit 64;;
    *) if [ -z "$WS" ]; then WS="$1"; shift; else echo "aggregate-runs: unexpected argument $1" >&2; exit 64; fi;;
  esac
done

[ -n "$WS" ] || { echo "aggregate-runs: a workspace directory is required" >&2; exit 64; }
[ -d "$WS" ] || { echo "aggregate-runs: workspace not found: $WS" >&2; exit 65; }
META="$WS/meta.json"
[ -f "$META" ] || { echo "aggregate-runs: meta.json not found in workspace: $META" >&2; exit 65; }
if ! jq -e . "$META" >/dev/null 2>&1; then
  echo "aggregate-runs: meta.json is not valid JSON: $META" >&2; exit 65
fi

# Sum a side's per-trial token usage + wall-time across its run-*/result.json files. Prefers
# .model_usage (camelCase cumulative, authoritative) and falls back to .usage (snake_case). Echoes a
# JSON object {input_tokens, output_tokens, cache_read_tokens, cache_creation_tokens, wall_seconds,
# trials, models:[...]} — empty (trials:0) when the side has no result.json.
side_usage() {
  local sidedir="$1" files=()
  if [ -d "$sidedir" ]; then
    while IFS= read -r -d '' f; do files+=("$f"); done \
      < <(find "$sidedir" -mindepth 2 -maxdepth 2 -name result.json -print0 2>/dev/null | LC_ALL=C sort -z)
  fi
  if [ "${#files[@]}" -eq 0 ]; then
    echo '{"input_tokens":0,"output_tokens":0,"cache_read_tokens":0,"cache_creation_tokens":0,"wall_seconds":0,"trials":0,"models":[]}'
    return 0
  fi
  jq -s '
    def toks:
      if (.model_usage // null | type) == "object" and ((.model_usage|length) > 0)
      then (.model_usage | [ to_entries[] ]
            | { i:(map(.value.inputTokens // 0)|add), o:(map(.value.outputTokens // 0)|add),
                cr:(map(.value.cacheReadInputTokens // 0)|add), cc:(map(.value.cacheCreationInputTokens // 0)|add),
                m:(map(.key)) })
      elif (.usage // null) != null
      then { i:(.usage.input_tokens // 0), o:(.usage.output_tokens // 0),
             cr:(.usage.cache_read_input_tokens // 0), cc:(.usage.cache_creation_input_tokens // 0), m:[] }
      else { i:0, o:0, cr:0, cc:0, m:[] } end;
    def wall: ((.duration_ms // .wall_ms_driver // 0) / 1000);
    reduce .[] as $r (
      {input_tokens:0,output_tokens:0,cache_read_tokens:0,cache_creation_tokens:0,wall_seconds:0,trials:0,models:[]};
      ($r|toks) as $t |
        .input_tokens          += $t.i
      | .output_tokens         += $t.o
      | .cache_read_tokens      += $t.cr
      | .cache_creation_tokens  += $t.cc
      | .wall_seconds           += ($r|wall)
      | .trials                 += 1
      | .models                  = ((.models + $t.m) | unique)
    )
  ' "${files[@]}"
}

# Flatten the CANDIDATE side's per-trial per-expectation PASS/FAIL into a 0/1 array (→ pass_rate).
candidate_expectation_pass() {
  local sidedir="$1" files=()
  if [ -d "$sidedir" ]; then
    while IFS= read -r -d '' f; do files+=("$f"); done \
      < <(find "$sidedir" -mindepth 2 -maxdepth 2 -name grading.json -print0 2>/dev/null | LC_ALL=C sort -z)
  fi
  if [ "${#files[@]}" -eq 0 ]; then echo '[]'; return 0; fi
  jq -s '[ .[] | (.expectations // [])[] | (if .passed then 1 else 0 end) ]' "${files[@]}"
}

# ---- walk the eval-<id> task dirs ------------------------------------------
TASK_DIRS=()
while IFS= read -r -d '' d; do TASK_DIRS+=("$d"); done \
  < <(find "$WS" -mindepth 1 -maxdepth 1 -type d -name 'eval-*' -print0 2>/dev/null \
      | LC_ALL=C sort -z -t- -k2 -n)
if [ "${#TASK_DIRS[@]}" -eq 0 ]; then
  echo "aggregate-runs: no eval-<id> task directories under $WS" >&2; exit 65
fi

TASKS_JSON="[]"
ALL_MODELS="[]"
CAND_OUT_TOTAL=0
BASE_OUT_TOTAL=0
for td in "${TASK_DIRS[@]}"; do
  id_raw="${td##*/eval-}"
  cmp="$td/comparison.json"
  if [ ! -f "$cmp" ] || ! jq -e '.primary_value != null' "$cmp" >/dev/null 2>&1; then
    echo "aggregate-runs: task $id_raw has no comparison.json with a primary_value ($cmp) — cannot build a gradeable benchmark" >&2
    exit 66
  fi
  cu="$(side_usage "$td/candidate")"
  bu="$(side_usage "$td/baseline")"
  ep="$(candidate_expectation_pass "$td/candidate")"

  ctrials="$(printf '%s' "$cu" | jq '.trials')"
  btrials="$(printf '%s' "$bu" | jq '.trials')"
  if [ "$ctrials" != "$btrials" ]; then
    echo "aggregate-runs: WARN task $id_raw has $ctrials candidate vs $btrials baseline trials — recording min as trials" >&2
  fi
  # expectation_pass is pooled from candidate grading.json files; if that count disagrees with the
  # candidate trial (result.json) count, pass_rate's denominator silently diverges from trials_per_task
  # (a crashed-but-graded or graded-but-crashed trial). Surface it — pass_rate is reported, not gated.
  ngrade="$(find "$td/candidate" -mindepth 2 -maxdepth 2 -name grading.json 2>/dev/null | grep -c . || true)"
  if [ "${ngrade:-0}" != "$ctrials" ]; then
    echo "aggregate-runs: WARN task $id_raw has $ngrade candidate grading.json vs $ctrials result.json — pass_rate denominator will not match trials_per_task" >&2
  fi

  # numeric id when possible (so HISTORY rows + partition-id ranges sort right), else string
  if printf '%s' "$id_raw" | grep -Eq '^[0-9]+$'; then idflag=(--argjson id "$id_raw"); else idflag=(--arg id "$id_raw"); fi

  task="$(jq -nc "${idflag[@]}" \
    --argjson cu "$cu" --argjson bu "$bu" --argjson ep "$ep" --slurpfile cmp "$cmp" '
    ($cmp[0]) as $c |
    {
      id: $id,
      trials: ([$cu.trials, $bu.trials] | min),
      primary_value: $c.primary_value,
      expectation_pass: $ep,
      candidate: { input_tokens:$cu.input_tokens, output_tokens:$cu.output_tokens,
                   cache_read_tokens:$cu.cache_read_tokens, cache_creation_tokens:$cu.cache_creation_tokens,
                   wall_seconds: (($cu.wall_seconds*100|round)/100) },
      baseline:  { input_tokens:$bu.input_tokens, output_tokens:$bu.output_tokens,
                   cache_read_tokens:$bu.cache_read_tokens, cache_creation_tokens:$bu.cache_creation_tokens,
                   wall_seconds: (($bu.wall_seconds*100|round)/100) }
    }
    # carry optional reference metrics through only when the comparator supplied them (plan §10, /review)
    | (if $c.recall_passk != null then .recall_passk = $c.recall_passk else . end)
    | (if $c.recall_at1 != null then .recall_at1 = $c.recall_at1 else . end)
    | (if ($c.precision_hits != null and $c.precision_total != null)
         then .precision_hits = $c.precision_hits | .precision_total = $c.precision_total else . end)
  ')"
  TASKS_JSON="$(jq -c --argjson t "$task" '. + [$t]' <<<"$TASKS_JSON")"
  ALL_MODELS="$(jq -c --argjson cu "$cu" --argjson bu "$bu" '(. + $cu.models + $bu.models) | unique' <<<"$ALL_MODELS")"
  CAND_OUT_TOTAL=$(( CAND_OUT_TOTAL + $(printf '%s' "$cu" | jq '.output_tokens') ))
  BASE_OUT_TOTAL=$(( BASE_OUT_TOTAL + $(printf '%s' "$bu" | jq '.output_tokens') ))
done

# ---- executor_model: meta override → single observed model → first observed (warn on >1) ----
EXEC_MODEL="$(jq -r '.executor_model // empty' "$META")"
n_models="$(jq 'length' <<<"$ALL_MODELS")"
if [ -z "$EXEC_MODEL" ]; then
  if [ "$n_models" -eq 1 ]; then
    EXEC_MODEL="$(jq -r '.[0]' <<<"$ALL_MODELS")"
  elif [ "$n_models" -gt 1 ]; then
    EXEC_MODEL="$(jq -r '.[0]' <<<"$ALL_MODELS")"
    echo "aggregate-runs: WARN runs span $n_models models ($(jq -c . <<<"$ALL_MODELS")); recording executor_model=$EXEC_MODEL — cost is single-model-priced, set meta.executor_model or split per model for a multi-model run (Phase D)" >&2
  fi
fi
if [ "$n_models" -gt 1 ] && [ -n "$(jq -r '.executor_model // empty' "$META")" ]; then
  echo "aggregate-runs: WARN runs span $n_models models but meta.executor_model pins one; cost prices all tokens at that model's rate" >&2
fi

# ---- length-confound heuristic (overridable by meta.length_confounded) ----
LEN_CONFOUNDED="$(jq -r '.length_confounded // empty' "$META")"
if [ -z "$LEN_CONFOUNDED" ]; then
  if [ "$BASE_OUT_TOTAL" -gt 0 ]; then
    LEN_CONFOUNDED="$(jq -nr --argjson c "$CAND_OUT_TOTAL" --argjson b "$BASE_OUT_TOTAL" --argjson t "$LEN_CONFOUND_THRESHOLD" \
      '($c/$b) as $r | if ($r > (1+$t)) or ($r < (1/(1+$t))) then "true" else "false" end')"
  else
    LEN_CONFOUNDED="false"
  fi
fi

# ---- assemble benchmark.json (top-level provenance from meta + tasks[]) ----
BENCH="$(jq -n \
  --slurpfile meta "$META" --argjson tasks "$TASKS_JSON" \
  --arg execmodel "$EXEC_MODEL" --argjson lenconf "$LEN_CONFOUNDED" \
  --arg skillov "$SKILL_OVERRIDE" --arg candov "$CAND_OVERRIDE" --arg baseov "$BASE_OVERRIDE" '
  ($meta[0]) as $m |
  {
    schema_version: ($m.schema_version // "benchmark-v1"),
    skill: (if $skillov != "" then $skillov else $m.skill end),
    candidate_ref: (if $candov != "" then $candov else $m.candidate_ref end),
    baseline_ref: (if $baseov != "" then $baseov else $m.baseline_ref end),
    executor_model: (if $execmodel != "" then $execmodel else $m.executor_model end),
    judge_model: $m.judge_model,
    cross_family_judge: $m.cross_family_judge,
    models_resolved_at: $m.models_resolved_at,
    executor_temperature: $m.executor_temperature,
    judge_temperature: $m.judge_temperature,
    auq_autoanswer_policy: $m.auq_autoanswer_policy,
    holdout_partition: $m.holdout_partition,
    position_swapped: $m.position_swapped,
    length_confounded: $lenconf,
    cross_family_agree: $m.cross_family_agree,
    judge_human_kappa: $m.judge_human_kappa,
    kappa_measured_at: $m.kappa_measured_at,
    comparator_verdict: $m.comparator_verdict,
    pointwise_score: $m.pointwise_score,
    pointwise_baseline_score: $m.pointwise_baseline_score,
    primary_metric: ($m.primary_metric // "quality_winrate_vs_baseline"),
    primary_null: ($m.primary_null // 0.5),
    tasks: $tasks
  }
  | with_entries(select(.value != null))')"

if [ -z "$BENCH" ]; then
  echo "aggregate-runs: failed to assemble benchmark.json" >&2; exit 65
fi

if [ -n "$OUT" ]; then
  printf '%s\n' "$BENCH" | jq . > "$OUT"
  echo "aggregate-runs: wrote $(jq '.tasks|length' <<<"$BENCH") task(s) → $OUT" >&2
else
  printf '%s\n' "$BENCH" | jq .
fi
