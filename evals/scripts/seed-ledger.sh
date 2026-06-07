#!/usr/bin/env bash
# evals/scripts/seed-ledger.sh — create the committed ledger files if absent.
#
# Seeds:
#   evals/HISTORY.md     — the human table header (single-sourced from ledger_history_header
#                          in evals/lib/ledger-append.sh, so the seed and the writer's
#                          create-if-absent path can never drift).
#   evals/history.jsonl  — an empty append target (the JSONL source of truth).
#
# Targets the LOCAL checkout's evals/ (script-relative), NOT _geniro_repo_root. The runtime
# writer (ledger_append) intentionally resolves _geniro_repo_root so every worktree appends to
# ONE shared committed ledger in the primary worktree; but seeding the initial committed files
# must land in the checkout you're committing from, so seeding is deliberately local.
#
# Idempotent: never clobbers a HISTORY.md that already has rows, never truncates history.jsonl.
# Run: bash evals/scripts/seed-ledger.sh
set -uo pipefail

_seed_dir="$(cd "$(dirname "$0")" && pwd)"
# shellcheck disable=SC1091
source "$_seed_dir/../lib/ledger-append.sh"

evals_dir="$(cd "$_seed_dir/.." && pwd)"
hist="$evals_dir/HISTORY.md"
log="$evals_dir/history.jsonl"

mkdir -p "$evals_dir"

if [ ! -f "$hist" ]; then
  ledger_history_header | atomic_state_write "$hist"
  echo "seeded $hist"
else
  echo "exists, left intact: $hist"
fi

if [ ! -f "$log" ]; then
  : > "$log"
  echo "seeded (empty) $log"
else
  echo "exists, left intact: $log"
fi
