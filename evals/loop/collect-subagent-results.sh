#!/usr/bin/env bash
# Wrap Claude-subagent executor output into the adapter result shape.
#
#   collect-subagent-results.sh <run-dir>
#
# The claude-subagent executor is the orchestrating session itself
# (adapters/claude-subagent.md § Executor protocol): each spawned subagent writes
# its verdict text beside the prompt it was given, and this turns those into the
# raw-<facet>.json files score.sh reads. Token usage is left empty on purpose —
# the subagent path is not metered, and inventing numbers would feed a cost
# column that means nothing.
#
# Two source shapes, checked in this order per trial directory:
#   result-<facet>.txt   every facet the trial ran, collected in ONE pass. A
#                        multi-facet module needs this: the single-file shape
#                        below carries the facet in an env var, so collecting a
#                        second facet means overwriting the first one's file and
#                        running again, and a missed pass silently scores that
#                        facet as zero findings.
#   result.txt           legacy single-facet shape; facet comes from $FACET.
# A trial directory carrying both prefers the per-facet files.
#
# Idempotent: re-running overwrites the raw files from the same sources.
set -euo pipefail

RUN="${1:-}"
[ -n "$RUN" ] || { echo "usage: collect-subagent-results.sh <run-dir>" >&2; exit 64; }
[ -d "$RUN/results" ] || { echo "no results/ under $RUN" >&2; exit 66; }

FACET="${FACET:-claims}"
wrapped=0
missing=""

wrap() { # <src> <trial-dir> <facet>
  jq -Rs '{type:"result", result:., is_error:false, usage:{}}' < "$1" > "$2/raw-$3.json"
  wrapped=$((wrapped + 1))
}

for trdir in "$RUN"/results/*/trial-*/; do
  [ -d "$trdir" ] || continue
  task="$(basename "$(dirname "${trdir%/}")")"
  trial="$(basename "${trdir%/}")"

  found_any=0
  for src in "$trdir"result-*.txt; do
    [ -e "$src" ] || continue
    found_any=1
    facet="$(basename "$src")"; facet="${facet#result-}"; facet="${facet%.txt}"
    if [ ! -s "$src" ]; then
      missing="$missing $task/$trial:$facet"
      continue
    fi
    wrap "$src" "$trdir" "$facet"
  done
  [ "$found_any" -eq 1 ] && continue

  src="$trdir/result.txt"
  if [ ! -s "$src" ]; then
    missing="$missing $task/$trial"
    continue
  fi
  wrap "$src" "$trdir" "$FACET"
done

echo "wrapped $wrapped result file(s)"
if [ -n "$missing" ]; then
  # Loud, not silent: an unwrapped trial scores as zero findings, which reads
  # identical to a run that found nothing and would quietly deflate recall.
  echo "MISSING result:$missing" >&2
  exit 1
fi
