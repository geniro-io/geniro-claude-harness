#!/usr/bin/env bash
# Query the append-only learnings log.
set -euo pipefail

LOG="${LEARNINGS_LOG:-.plugin/learnings.jsonl}"

# query_learnings <tag> — every entry carrying <tag>, newest first.
query_learnings() {
  local tag="$1"
  [ -f "$LOG" ] || return 0
  jq -c --arg t "$tag" 'select(.tags | index($t))' "$LOG" | tail -r
}
