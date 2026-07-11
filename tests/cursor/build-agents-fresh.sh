#!/usr/bin/env bash
# Freshness check for cursor/agents/ (generated from agents/*.md).
#
# Run: bash tests/cursor/build-agents-fresh.sh
#
# Regenerates the Cursor agent copies into a temp dir and diffs them against
# the committed cursor/agents/. A mismatch means agents/*.md changed without
# re-running scripts/build-cursor-agents.sh (or the copy was hand-edited).

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
TMP_OUT="$(mktemp -d)"
trap 'rm -rf "$TMP_OUT"' EXIT

if ! bash "$REPO_ROOT/scripts/build-cursor-agents.sh" "$TMP_OUT" 2>/dev/null; then
  echo "FAIL: scripts/build-cursor-agents.sh errored" >&2
  exit 1
fi

if diff -r "$TMP_OUT" "$REPO_ROOT/cursor/agents" >/dev/null 2>&1; then
  echo "PASS: cursor/agents/ is fresh (matches agents/*.md sources)"
  exit 0
fi

echo "FAIL: cursor/agents/ is stale — run scripts/build-cursor-agents.sh and commit the result. Diff:" >&2
diff -r "$TMP_OUT" "$REPO_ROOT/cursor/agents" >&2
exit 1
