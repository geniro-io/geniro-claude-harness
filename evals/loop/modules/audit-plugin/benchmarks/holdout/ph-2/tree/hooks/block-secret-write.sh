#!/usr/bin/env bash
# Block writes that would commit a credential.
set -euo pipefail

INPUT="$(cat)"
CONTENT="$(printf '%s' "$INPUT" | jq -r '.tool_input.content // empty')"

if printf '%s' "$CONTENT" | grep -Eq '(api[_-]?key|secret|token)[[:space:]]*[:=]'; then
  echo "Safety blocked [secret-write]: credential-shaped content" >&2
  exit 2
fi
exit 0
