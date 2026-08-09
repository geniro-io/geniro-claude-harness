#!/usr/bin/env bash
# Executor adapter: cursor-agent CLI, read-only ask mode.
#
#   cursor-cli.sh <model> <workspace> <prompt-file> <out-json> <err-log>
#
# Ask mode: read-only AND the answer lands in the result text (plan mode routes
# long output into its plan buffer, which silently drops it). One call, no
# retries — run.sh owns the retry/contract policy.
set -euo pipefail
MODEL="$1"; WORKSPACE="$2"; PROMPT="$3"; OUT="$4"; ERR="$5"
cursor-agent -p --output-format json --model "$MODEL" --mode ask \
  --workspace "$WORKSPACE" --trust < "$PROMPT" > "$OUT" 2> "$ERR"
