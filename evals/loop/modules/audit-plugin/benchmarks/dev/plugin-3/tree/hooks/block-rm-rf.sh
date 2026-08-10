#!/usr/bin/env bash
# Block recursive deletes that reach outside the workspace.
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=../lib/safety.sh
source "$HERE/../lib/safety.sh"

INPUT="$(cat)"
CMD="$(printf '%s' "$INPUT" | jq -r '.tool_input.command // empty')"

ALLOW="$(read_allow_patterns)" || exit 0

printf '%s' "$CMD" | grep -Eq 'rm +(-[a-zA-Z]* )*-[a-zA-Z]*r[a-zA-Z]* ' || exit 0

case "$ALLOW" in
  *recursive-delete*) exit 0 ;;
esac

echo "Safety blocked [recursive-delete]: rm -r outside the workspace" >&2
exit 2
