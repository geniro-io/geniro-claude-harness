#!/usr/bin/env bash
# The experiment cycle, mechanical part. The orchestrating session (or the
# /eval-loop skill) owns the judgment parts: error analysis, the EXP file,
# judge subagents, and the promotion decision.
#
#   loop.sh screen  --module M --variant <dir> [--trials N] [--model M]
#                   [--baseline <run-dir>] [--tasks <dir>] [--yes]
#   loop.sh confirm --module M --variant <dir> [--trials N] --model M2 [--yes]
#   loop.sh verdict <candidate-run> <baseline-run>
#
# screen  = probe (1 paid call, prints extrapolated cost) then, only with --yes,
#           sweep candidate + champion baseline on the dev set and prep judging.
# confirm = the same flow on the HOLDOUT set — run it only after a screen win,
#           and on a second model family (pass --model explicitly).
# verdict = finish scoring both runs and print the paired comparison.
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
CMD="${1:-}"; shift || true

case "$CMD" in
  screen|confirm)
    MODULE=""; VARIANT=""; TRIALS=2; MODEL="cursor-composer-2.5"; BASELINE=""; TASKS=""; YES=0
    MODEL_SET=0
    while [ $# -gt 0 ]; do
      case "$1" in
        --module) MODULE="$2"; shift 2;;
        --variant) VARIANT="$2"; shift 2;;
        --trials) TRIALS="$2"; shift 2;;
        --model) MODEL="$2"; MODEL_SET=1; shift 2;;
        --baseline) BASELINE="$2"; shift 2;;
        --tasks) TASKS="$2"; shift 2;;
        --yes) YES=1; shift;;
        *) echo "unknown arg: $1" >&2; exit 64;;
      esac
    done
    [ -n "$MODULE" ] && [ -n "$VARIANT" ] || { echo "need --module and --variant" >&2; exit 64; }
    if [ "$CMD" = "confirm" ]; then
      [ -n "$TASKS" ] || TASKS="$HERE/modules/$MODULE/benchmarks/holdout"
      [ "$MODEL_SET" -eq 1 ] || { echo "confirm requires an explicit --model (second family)" >&2; exit 64; }
    else
      [ -n "$TASKS" ] || TASKS="$HERE/modules/$MODULE/benchmarks/dev"
    fi
    echo "== probe (1 paid call) =="
    bash "$HERE/run.sh" --module "$MODULE" --variant "$VARIANT" --tasks "$TASKS" --model "$MODEL" --probe \
      --out "$HERE/runs/scratch/probe-$$"
    rm -rf "$HERE/runs/scratch/probe-$$"
    if [ "$YES" -ne 1 ]; then
      echo "== probe only. Re-run with --yes to launch the sweep =="
      exit 0
    fi
    STAMP="$(date -u +%Y%m%dT%H%M%SZ)"
    CAND_OUT="$HERE/runs/scratch/$STAMP-$CMD-$(basename "$VARIANT")"
    echo "== sweep: candidate =="
    bash "$HERE/run.sh" --module "$MODULE" --variant "$VARIANT" --tasks "$TASKS" \
      --model "$MODEL" --trials "$TRIALS" --out "$CAND_OUT"
    if [ -z "$BASELINE" ]; then
      BASELINE="$HERE/runs/scratch/$STAMP-$CMD-champion"
      echo "== sweep: champion baseline (cache makes unchanged calls free) =="
      bash "$HERE/run.sh" --module "$MODULE" --tasks "$TASKS" \
        --model "$MODEL" --trials "$TRIALS" --out "$BASELINE"
    fi
    echo "== prep judging =="
    bash "$HERE/score.sh" "$CAND_OUT" --phase prep --tasks "$TASKS"
    bash "$HERE/score.sh" "$BASELINE" --phase prep --tasks "$TASKS"
    cat <<EOF
== next: judge, then verdict ==
Primary (free): spawn blind Claude subagents per adapters/claude-subagent.md
  — one per results/*/trial-*/judge-prompt.txt in BOTH runs, each Writes match.json.
Fallback (paid): score.sh <run> --phase judge --judge-model gpt-5.2
Then:
  bash loop.sh verdict "$CAND_OUT" "$BASELINE"
EOF
    ;;
  verdict)
    CAND="$1"; BASE="$2"
    bash "$HERE/score.sh" "$CAND" --phase finish
    bash "$HERE/score.sh" "$BASE" --phase finish
    bash "$HERE/compare.sh" "$CAND" "$BASE"
    ;;
  *)
    sed -n '2,16p' "$0"
    exit 64
    ;;
esac
