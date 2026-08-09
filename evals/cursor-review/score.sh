#!/usr/bin/env bash
# Score a driver run: parse findings, judge against ground truth, emit metrics.
#
#   score.sh <run-dir> [--phase prep|judge|finish|all] [--judge-model M] [--tasks <dir>]
#
# Phases:
#   prep   — parse raw results into findings.json + write judge-prompt.txt per trial
#   judge  — run the fallback cursor-agent judge for any trial missing match.json
#            (the primary path is the orchestrating Claude session spawning its own
#             blind judge subagents that Write match.json directly; then skip this)
#   finish — extract verdicts, compute per-task metrics, aggregate metrics.json
#   all    — prep + judge + finish
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
[ -n "$TASKS" ] || TASKS="$(jq -r '.tasks' "$RUN/meta.json")"

trial_dirs() { ls -d "$RUN"/results/*/trial-*/ 2>/dev/null; }
task_of() { basename "$(dirname "${1%/}")"; }

do_prep() {
  for trdir in $(trial_dirs); do
    task_id="$(task_of "$trdir")"
    gt="$TASKS/$task_id/ground_truth.json"
    [ -f "$gt" ] || { echo "no ground truth for $task_id — skipping" >&2; continue; }
    python3 "$HERE/eval_lib.py" parse "$trdir"raw-*.json > "$trdir/findings.json"
    python3 "$HERE/eval_lib.py" judgeprompt "$gt" "$trdir/findings.json" > "$trdir/judge-prompt.txt"
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
    python3 "$HERE/eval_lib.py" extract "$trdir/judge-raw.json" > "$trdir/match.json" || rm -f "$trdir/match.json"
  done
}

do_finish() {
  rows="$RUN/task-rows.jsonl"
  : > "$rows"
  missing=0
  for trdir in $(trial_dirs); do
    task_id="$(task_of "$trdir")"
    trial="$(basename "$trdir")"
    gt="$TASKS/$task_id/ground_truth.json"
    [ -f "$gt" ] || continue
    if [ ! -f "$trdir/match.json" ] && [ -f "$trdir/judge-raw.json" ]; then
      python3 "$HERE/eval_lib.py" extract "$trdir/judge-raw.json" > "$trdir/match.json" || rm -f "$trdir/match.json"
    fi
    if [ ! -f "$trdir/match.json" ]; then
      echo "[finish] MISSING match.json: $task_id $trial" >&2
      missing=$((missing + 1))
      continue
    fi
    python3 "$HERE/eval_lib.py" metrics "$RUN/stage/$task_id/task.json" "$gt" \
      "$trdir/findings.json" "$trdir/match.json" "$trdir" > "$trdir/task-metrics.json"
    jq -c --arg trial "$trial" '. + {trial:$trial}' "$trdir/task-metrics.json" >> "$rows"
    echo "[scored] $task_id $trial: $(jq -r '"recall_must=\(.recall_must) noise=\(.noise) findings=\(.findings_total)"' "$trdir/task-metrics.json")"
  done
  [ "$missing" -eq 0 ] || { echo "[finish] $missing trials unjudged — run judge phase or supply match.json" >&2; exit 65; }
  jq -s '{
    rows: .,
    mean: {
      recall_must: (map(.recall_must // empty) | if length>0 then (add/length) else null end),
      recall_weighted: (map(.recall_weighted // empty) | if length>0 then (add/length) else null end),
      noise: (map(.noise) | add/length),
      findings_total: (map(.findings_total) | add/length),
      plausible_real: (map(.plausible_real) | add/length),
      tokens_in: (map(.tokens_in) | add/length),
      tokens_out: (map(.tokens_out) | add/length)
    }
  }' "$rows" > "$RUN/metrics.json"
  jq '.mean' "$RUN/metrics.json"
}

case "$PHASE" in
  prep) do_prep;;
  judge) do_judge;;
  finish) do_finish;;
  all) do_prep; do_judge; do_finish;;
  *) echo "unknown phase: $PHASE" >&2; exit 64;;
esac
