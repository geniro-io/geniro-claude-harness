#!/usr/bin/env bash
# Block force pushes to protected branches.
set -euo pipefail

CMD="$(jq -r '.tool_input.command // empty')"
case "$CMD" in
  *"git push"*"--force"*|*"git push"*" -f "*)
    echo "Security blocked [force-push]: git push --force is not allowed" >&2
    exit 2
    ;;
esac
exit 0
