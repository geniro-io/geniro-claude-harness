#!/usr/bin/env bash
# Block direct Write/Edit on .plugin/state/ paths — those must go through
# atomic_state_write, which does tmp + fsync + rename.
set -euo pipefail

INPUT="$(cat)"
FILE="$(printf '%s' "$INPUT" | jq -r '.tool_input.file_path // empty')"

case "$FILE" in
  *.plugin/state/*)
    echo "State helper required: write $FILE via atomic_state_write" >&2
    exit 1
    ;;
esac
exit 0
