#!/usr/bin/env bash
# Checks the two runtime manifests stay in lockstep.
#
# Run: bash tests/cursor/manifest-sync.sh
#
# Coverage:
#   - .cursor-plugin/plugin.json is valid JSON with the required name field.
#   - version matches .claude-plugin/plugin.json (the release workflow bumps
#     both; a mismatch means one was edited by hand).
#   - The component paths the Cursor manifest declares exist on disk.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
CLAUDE_MANIFEST="$REPO_ROOT/.claude-plugin/plugin.json"
CURSOR_MANIFEST="$REPO_ROOT/.cursor-plugin/plugin.json"

TESTS_RUN=0
TESTS_FAILED=0
pass() { TESTS_RUN=$((TESTS_RUN + 1)); echo "PASS: $1"; }
fail() { TESTS_RUN=$((TESTS_RUN + 1)); TESTS_FAILED=$((TESTS_FAILED + 1)); echo "FAIL: $1" >&2; }

if jq -e '.name | test("^[a-z0-9]([a-z0-9.-]*[a-z0-9])?$")' "$CURSOR_MANIFEST" >/dev/null 2>&1; then
  pass "cursor manifest has a valid name"
else
  fail "cursor manifest name missing or invalid"
fi

CLAUDE_V="$(jq -r '.version' "$CLAUDE_MANIFEST" 2>/dev/null)"
CURSOR_V="$(jq -r '.version' "$CURSOR_MANIFEST" 2>/dev/null)"
if [ -n "$CLAUDE_V" ] && [ "$CLAUDE_V" = "$CURSOR_V" ]; then
  pass "manifest versions in lockstep ($CLAUDE_V)"
else
  fail "manifest version mismatch: claude=$CLAUDE_V cursor=$CURSOR_V"
fi

for key in skills agents hooks; do
  p="$(jq -r --arg k "$key" '.[$k] // ""' "$CURSOR_MANIFEST")"
  if [ -n "$p" ] && [ -e "$REPO_ROOT/${p#./}" ]; then
    pass "cursor manifest $key path exists ($p)"
  else
    fail "cursor manifest $key path missing on disk: $p"
  fi
done

echo
echo "Tests run: $TESTS_RUN, failed: $TESTS_FAILED"
exit "$TESTS_FAILED"
