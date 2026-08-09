#!/usr/bin/env bash
# Paired candidate-vs-baseline verdict over two scored runs.
#
#   compare.sh <candidate-run-dir> <baseline-run-dir> [--seed N]
#
# Pairs tasks by id (trials averaged per task first — the task is the unit of
# randomization), then reports per-task deltas, win/loss/tie counts, and a seeded
# task-clustered bootstrap CI of the mean delta for recall_must and noise.
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=/dev/null
source "$HERE/../lib/eval-stats.sh"

CAND="$(cd "$1" && pwd)"; BASE="$(cd "$2" && pwd)"; shift 2
SEED=20260809
while [ $# -gt 0 ]; do
  case "$1" in
    --seed) SEED="$2"; shift 2;;
    *) echo "unknown arg: $1" >&2; exit 64;;
  esac
done
[ -f "$CAND/metrics.json" ] && [ -f "$BASE/metrics.json" ] || { echo "score both runs first" >&2; exit 66; }

jq -n --slurpfile c "$CAND/metrics.json" --slurpfile b "$BASE/metrics.json" \
      --argjson seed "$SEED" "
$GENIRO_EVAL_STATS_JQ_DEFS
  def task_means(\$rows; \$field):
    reduce \$rows[] as \$r ({}; .[\$r.task] += [\$r[\$field]])
    | with_entries(.value |= (map(select(. != null)) | if length>0 then add/length else null end));

  (\$c[0].rows) as \$crows | (\$b[0].rows) as \$brows
  | task_means(\$crows; \"recall_must\") as \$cr
  | task_means(\$brows; \"recall_must\") as \$br
  | task_means(\$crows; \"noise\") as \$cn
  | task_means(\$brows; \"noise\") as \$bn
  | ([\$cr, \$br | keys] | .[0] as \$a | .[1] as \$b2 | \$a | map(select(. as \$k | \$b2 | index(\$k)))) as \$common
  | (\$common | map(select(\$cr[.] != null and \$br[.] != null) | {task: ., delta: (\$cr[.] - \$br[.])})) as \$rd
  | (\$common | map({task: ., delta: (\$cn[.] - \$bn[.])})) as \$nd
  | (\$rd | map(.delta)) as \$rvec
  | (\$nd | map(.delta)) as \$nvec
  | {
      tasks_paired: (\$common | length),
      recall_must: {
        per_task: \$rd,
        mean_delta: mean(\$rvec),
        wins: (\$rvec | map(select(. > 0)) | length),
        losses: (\$rvec | map(select(. < 0)) | length),
        ties: (\$rvec | map(select(. == 0)) | length),
        ci95: bootstrap_ci(\$rvec; 2000; \$seed; 0.025; 0.975)
      },
      noise: {
        per_task: \$nd,
        mean_delta: mean(\$nvec),
        ci95: bootstrap_ci(\$nvec; 2000; \$seed + 1; 0.025; 0.975)
      }
    }
  | . + { verdict:
      ( if .recall_must.ci95[0] != null and .recall_must.ci95[0] > 0 and (.noise.ci95[0] == null or .noise.ci95[0] <= 0.0001 or .noise.mean_delta <= 0)
          then \"candidate better on recall, noise not worse\"
        elif .recall_must.ci95[1] != null and .recall_must.ci95[1] < 0
          then \"candidate WORSE on recall\"
        elif .noise.ci95[1] != null and .noise.ci95[1] < 0 and (.recall_must.ci95[0] == null or .recall_must.mean_delta >= 0)
          then \"candidate better on noise, recall held\"
        else \"tie / inside CI — no promotion\" end) }
"
