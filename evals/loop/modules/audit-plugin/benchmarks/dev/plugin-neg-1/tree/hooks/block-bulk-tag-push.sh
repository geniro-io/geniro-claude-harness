#!/usr/bin/env bash
# Block `git push --tags`: a bulk tag push publishes every local tag, including
# ones cut on abandoned branches. Pushing one named tag stays allowed.
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=../lib/safety.sh
source "$HERE/../lib/safety.sh"

INPUT="$(cat)"
CMD="$(printf '%s' "$INPUT" | jq -r '.tool_input.command // empty')"

if ! ALLOW="$(read_allow_patterns)"; then
  echo "Safety blocked [bulk-tag-push]: allowlist unreadable, refusing to allow" >&2
  exit 2
fi

printf '%s' "$CMD" | grep -Eq 'git +push +.*--tags' || exit 0

case " $ALLOW " in
  *" bulk-tag-push "*) exit 0 ;;
esac

echo "Safety blocked [bulk-tag-push]: git push --tags publishes every local tag" >&2
exit 2
