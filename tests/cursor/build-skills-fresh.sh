#!/usr/bin/env bash
# Freshness check for cursor/skills/ (generated from skills/*/SKILL.md).
#
# Run: bash tests/cursor/build-skills-fresh.sh
#
# Regenerates the Cursor skill copies into a temp dir and diffs them against
# the committed cursor/skills/. A mismatch means skills/*/SKILL.md changed
# without re-running scripts/build-cursor-skills.sh (or the copy was
# hand-edited).

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
TMP_OUT="$(mktemp -d)"
trap 'rm -rf "$TMP_OUT"' EXIT

if ! bash "$REPO_ROOT/scripts/build-cursor-skills.sh" "$TMP_OUT" 2>/dev/null; then
  echo "FAIL: scripts/build-cursor-skills.sh errored" >&2
  exit 1
fi

if diff -r "$TMP_OUT" "$REPO_ROOT/cursor/skills" >/dev/null 2>&1; then
  echo "PASS: cursor/skills/ is fresh (matches skills/*/SKILL.md sources)"
  exit 0
fi

echo "FAIL: cursor/skills/ is stale — run scripts/build-cursor-skills.sh and commit the result. Diff:" >&2
diff -r "$TMP_OUT" "$REPO_ROOT/cursor/skills" >&2
exit 1
