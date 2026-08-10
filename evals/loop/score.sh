#!/usr/bin/env bash
# Score a run: parse results, judge against rubrics, emit per-trial rows + reducers.
#
#   score.sh <run-dir> [--phase prep|judge|finish|all] [--judge-model M] [--tasks <dir>]
#
# Phases:
#   prep   — parse raw results into findings.json + write judge-prompt.txt per trial
#   judge  — run the fallback CLI judge for any trial missing match.json
#            (the primary path is the orchestrating Claude session spawning its own
#             blind judge subagents that Write match.json directly; then skip this)
#   finish — extract verdicts, compute per-trial metrics + pass, aggregate with
#            trial reducers (mean / pass@k / pass^k) into metrics.json
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
RUN="$(cd "$1" && pwd)"; shift
PHASE="all"
JUDGE_MODEL="gpt-5.2"
TASKS=""
while [ $# -gt 0 ]; do
  case "$1" in
    --phase) PHASE="$2"; shift 2;;
    --judge-model) JUDGE_MODEL="$2"; shift 2;;
    --tasks) TASKS="$2"; shift 2;;
    *) echo "unknown arg: $1" >&2; exit 64;;
  esac
done
[ -n "$TASKS" ] || TASKS="$(jq -r '.tasks' "$RUN/spec.json")"
MODULE="$(jq -r '.module' "$RUN/spec.json")"
TARGET="$HERE/modules/$MODULE/target.json"
PARSER="$(jq -r '.parser // "review-findings"' "$TARGET")"
PASS_EXPR="$(jq -r '.pass_expr // "false"' "$TARGET")"
NEG_EXPR="$(jq -r '.negative_pass_expr // "false"' "$TARGET")"

trial_dirs() { ls -d "$RUN"/results/*/trial-*/ 2>/dev/null; }
task_of() { basename "$(dirname "${1%/}")"; }

do_prep() {
  for trdir in $(trial_dirs); do
    task_id="$(task_of "$trdir")"
    rubric="$TASKS/$task_id/rubric.json"
    [ -f "$rubric" ] || { echo "no rubric for $task_id — skipping" >&2; continue; }
    python3 "$HERE/loop_lib.py" parse --parser "$PARSER" "$trdir"raw-*.json > "$trdir/findings.json"
    python3 "$HERE/loop_lib.py" judgeprompt "$rubric" "$trdir/findings.json" > "$trdir/judge-prompt.txt"
    echo "[prep] $task_id $(basename "$trdir"): $(jq 'length' "$trdir/findings.json") findings"
  done
}

do_judge() {
  for trdir in $(trial_dirs); do
    [ -f "$trdir/match.json" ] && continue
    [ -f "$trdir/judge-prompt.txt" ] || continue
    task_id="$(task_of "$trdir")"
    echo "[judge] $task_id $(basename "$trdir") via $JUDGE_MODEL"
    cursor-agent -p --output-format json --model "$JUDGE_MODEL" --trust \
      < "$trdir/judge-prompt.txt" > "$trdir/judge-raw.json" 2>>"$RUN/judge-err.log" || true
    python3 "$HERE/loop_lib.py" extract "$trdir/judge-raw.json" > "$trdir/match.json" || rm -f "$trdir/match.json"
  done
}

do_finish() {
  rows="$RUN/task-rows.jsonl"
  : > "$rows"
  missing=0
  for trdir in $(trial_dirs); do
    task_id="$(task_of "$trdir")"
    trial="$(basename "$trdir")"
    rubric="$TASKS/$task_id/rubric.json"
    [ -f "$rubric" ] || continue
    if [ ! -f "$trdir/match.json" ] && [ -f "$trdir/judge-raw.json" ]; then
      python3 "$HERE/loop_lib.py" extract "$trdir/judge-raw.json" > "$trdir/match.json" || rm -f "$trdir/match.json"
    fi
    if [ ! -f "$trdir/match.json" ]; then
      echo "[finish] MISSING match.json: $task_id $trial" >&2
      missing=$((missing + 1))
      continue
    fi
    python3 "$HERE/loop_lib.py" metrics "$RUN/stage/$task_id/task.json" "$rubric" \
      "$trdir/findings.json" "$trdir/match.json" "$trdir" > "$trdir/task-metrics.json"
    if jq -e 'if .negative then '"$NEG_EXPR"' else '"$PASS_EXPR"' end' \
         "$trdir/task-metrics.json" >/dev/null; then pass=true; else pass=false; fi
    jq -c --arg trial "$trial" --argjson pass "$pass" '. + {trial:$trial, pass:$pass}' \
      "$trdir/task-metrics.json" >> "$rows"
    echo "[scored] $task_id $trial: $(jq -r '"recall_must=\(.recall_must) noise=\(.noise) findings=\(.findings_total)"' "$trdir/task-metrics.json") pass=$pass"
  done
  [ "$missing" -eq 0 ] || { echo "[finish] $missing trials unjudged — run judge phase or supply match.json" >&2; exit 65; }
  jq -s '
    def mean_of(f): map(f // empty) | if length>0 then (add/length) else null end;
    {
      rows: .,
      mean: {
        recall_must: mean_of(.recall_must),
        recall_weighted: mean_of(.recall_weighted),
        noise: (map(.noise) | add/length),
        noise_strict: mean_of(.noise_strict),
        nitpick: mean_of(.nitpick),
        findings_total: (map(.findings_total) | add/length),
        plausible_real: (map(.plausible_real) | add/length),
        tokens_in: (map(.tokens_in) | add/length),
        tokens_out: (map(.tokens_out) | add/length)
      },
      reducers: (group_by(.task) | map({
          task: .[0].task,
          trials: length,
          pass_rate: ((map(select(.pass)) | length) / length),
          pass_at_k: (any(.pass)),
          pass_hat_k: (all(.pass))
        }) as $per_task
        | {
            per_task: $per_task,
            pass_rate: ($per_task | map(.pass_rate) | add/length),
            pass_at_k: ($per_task | map(select(.pass_at_k)) | length / ($per_task|length)),
            pass_hat_k: ($per_task | map(select(.pass_hat_k)) | length / ($per_task|length))
          })
    }' "$rows" > "$RUN/metrics.json"
  jq '{mean, reducers: (.reducers | del(.per_task))}' "$RUN/metrics.json"
}

case "$PHASE" in
  prep) do_prep;;
  judge) do_judge;;
  finish) do_finish;;
  all) do_prep; do_judge; do_finish;;
  *) echo "unknown phase: $PHASE" >&2; exit 64;;
esac
