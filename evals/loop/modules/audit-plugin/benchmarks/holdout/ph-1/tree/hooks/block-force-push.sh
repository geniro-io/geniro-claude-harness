#!/usr/bin/env bash
set -euo pipefail
CMD="$(cat | jq -r '.tool_input.command // empty')"
case "$CMD" in
  *"git push"*"--force"*) echo "blocked: force push" >&2; exit 2 ;;
esac
exit 0
