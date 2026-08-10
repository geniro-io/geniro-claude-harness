#!/usr/bin/env bash
# Block `git push --tags`: a bulk tag push publishes every local tag, including
# ones cut on abandoned branches. Pushing one named tag stays allowed.
#
# Out of reach by construction: an alias whose expansion supplies --tags never
# puts the flag in the command string, so no string guard can see it.
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=../lib/safety.sh
source "$HERE/../lib/safety.sh"

INPUT="$(cat)"
# A jq failure must not leave through set -e with a status the runtime reads as
# anything but this hook's own deny code.
if ! CMD="$(printf '%s' "$INPUT" | jq -r '.tool_input.command // empty')"; then
  echo "Safety blocked [bulk-tag-push]: unparseable hook input, refusing to allow" >&2
  exit 2
fi

if ! ALLOW="$(read_allow_patterns)"; then
  echo "Safety blocked [bulk-tag-push]: allowlist unreadable, refusing to allow" >&2
  exit 2
fi

# Token scan, not a regex over the raw string. git's global options legally sit
# between the command and its subcommand (`git -C dir push`, `git -c k=v push`),
# so a pattern requiring the two to be adjacent lets those forms through.
# Matching whole tokens also keeps `--follow-tags` out of the deny path.
# $CMD is deliberately unquoted here — word splitting is the tokenizer.
is_git=0; has_push=0; has_tags=0
# shellcheck disable=SC2086
for tok in $CMD; do
  case "$tok" in
    git)     is_git=1 ;;
    push)    [ "$is_git" -eq 1 ] && has_push=1 ;;
    --tags)  has_tags=1 ;;
  esac
done
[ "$has_push" -eq 1 ] && [ "$has_tags" -eq 1 ] || exit 0

case " $ALLOW " in
  *" bulk-tag-push "*) exit 0 ;;
esac

echo "Safety blocked [bulk-tag-push]: git push --tags publishes every local tag" >&2
exit 2
