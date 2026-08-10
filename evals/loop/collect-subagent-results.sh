#!/usr/bin/env bash
# Wrap Claude-subagent executor output into the adapter result shape.
#
#   collect-subagent-results.sh <run-dir>
#
# The claude-subagent executor is the orchestrating session itself
# (adapters/claude-subagent.md § Executor protocol): each spawned subagent writes
# its verdict text to <trial-dir>/result.txt, and this turns those into the
# raw-<facet>.json files score.sh reads. Token usage is left empty on purpose —
# the subagent path is not metered, and inventing numbers would feed a cost
# column that means nothing.
#
# Idempotent: re-running overwrites the raw files from the same result.txt.
set -euo pipefail

RUN="${1:-}"
[ -n "$RUN" ] || { echo "usage: collect-subagent-results.sh <run-dir>" >&2; exit 64; }
[ -d "$RUN/results" ] || { echo "no results/ under $RUN" >&2; exit 66; }

FACET="${FACET:-claims}"
wrapped=0
missing=""

for trdir in "$RUN"/results/*/trial-*/; do
  [ -d "$trdir" ] || continue
  task="$(basename "$(dirname "${trdir%/}")")"
  src="$trdir/result.txt"
  if [ ! -s "$src" ]; then
    missing="$missing $task/$(basename "${trdir%/}")"
    continue
  fi
  jq -Rs '{type:"result", result:., is_error:false, usage:{}}' < "$src" \
    > "$trdir/raw-$FACET.json"
  wrapped=$((wrapped + 1))
done

echo "wrapped $wrapped trial(s) into raw-$FACET.json"
if [ -n "$missing" ]; then
  # Loud, not silent: an unwrapped trial scores as zero findings, which reads
  # identical to a run that found nothing and would quietly deflate recall.
  echo "MISSING result.txt:$missing" >&2
  exit 1
fi
