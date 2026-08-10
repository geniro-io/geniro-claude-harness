#!/usr/bin/env bash
# Block a push that deletes a remote branch.
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=../lib/retry.sh
source "$HERE/../lib/retry.sh"

INPUT="$(cat)"
CMD="$(printf '%s' "$INPUT" | jq -r '.tool_input.command // empty')"

ALLOW="$(with_retry read_allow_patterns)"

printf '%s' "$CMD" | grep -q 'delete' || exit 0

case " $ALLOW " in
  *" branch-delete "*) exit 0 ;;
esac

echo "Safety blocked [branch-delete]: this push would delete a remote branch" >&2
exit 2
