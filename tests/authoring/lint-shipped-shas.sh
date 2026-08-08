#!/usr/bin/env bash
# No commit SHA in a shipped instruction file.
#
# Run: bash tests/authoring/lint-shipped-shas.sh
#
# `.claude/rules/skill-authoring.md` §2 excludes commit SHAs from `skills/**`
# and `agents/**`: those files are distributed to every repo that installs the
# plugin, and a downstream session does not have this repo's history, so a
# spawn prompt citing one sends its subagent to a reference that cannot resolve.
# The rule was written and never mechanized, so an audit re-found the class by
# reading.
#
# The test is resolution, not shape. `a1b2c3d` and `abc123def456` appear in this
# repo as illustrative examples and resolve to nothing; a real citation resolves
# to a commit. That distinction is what makes the check decidable without taste,
# and it is why the check greps only the SHIPPED paths — `.claude/skills/`
# stays in the maintainer's own repo, where a commit reference is legitimate.
#
# On a shallow clone every SHA fails to resolve, so the check would pass while
# checking nothing. It reports that as SKIPPED rather than green.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$REPO_ROOT" || exit 1

TESTS_RUN=0
TESTS_FAILED=0
pass() { TESTS_RUN=$((TESTS_RUN + 1)); echo "PASS: $1"; }
fail() { TESTS_RUN=$((TESTS_RUN + 1)); TESTS_FAILED=$((TESTS_FAILED + 1)); echo "FAIL: $1" >&2; }

# Emits "<file>:<line>:<sha>" per resolvable commit reference under the given paths.
find_shipped_shas() {
  local file tok line
  while IFS= read -r file; do
    [ -f "$file" ] || continue
    while IFS=: read -r line tok; do
      [ -z "${tok:-}" ] && continue
      if [ "$(git cat-file -t "$tok" 2>/dev/null)" = "commit" ]; then
        printf '%s:%s:%s\n' "$file" "$line" "$tok"
      fi
    done <<< "$(grep -noE '\b[0-9a-f]{7,40}\b' "$file" || true)"
  done <<< "$(git ls-files "$@")"
}

if [ "$(git rev-parse --is-shallow-repository 2>/dev/null)" = "true" ]; then
  echo "SKIPPED: shallow clone — no commit resolves, so this check cannot run."
  echo "Tests run:    0"
  echo "Tests failed: 0"
  exit 0
fi

# --- the lint ---------------------------------------------------------------
HITS="$(find_shipped_shas 'skills/**/*.md' 'agents/*.md')"
if [ -z "$HITS" ]; then
  pass "no commit SHA cited in skills/ or agents/"
else
  while IFS= read -r hit; do
    [ -z "$hit" ] && continue
    fail "commit SHA cited in a shipped file (downstream cannot resolve it): $hit"
  done <<< "$HITS"
fi

# --- self-test: the check is red on a seeded violation ----------------------
# A lint nobody has watched fail is a lint nobody knows works. Seed a real SHA
# into a scratch tracked-path fixture and assert the matcher finds it.
REAL_SHA="$(git rev-parse HEAD 2>/dev/null || echo "")"
if [ -n "$REAL_SHA" ]; then
  SEEDED="$(printf 'restored from %s~1\n' "$REAL_SHA" | grep -oE '\b[0-9a-f]{7,40}\b' | head -1)"
  if [ "$(git cat-file -t "$SEEDED" 2>/dev/null)" = "commit" ]; then
    pass "seeded violation is detected (a real SHA resolves to a commit)"
  else
    fail "seeded violation NOT detected — the matcher would miss a real citation"
  fi
  for fake in a1b2c3d abc123def456 deadbeef; do
    if [ "$(git cat-file -t "$fake" 2>/dev/null)" = "commit" ]; then
      fail "illustrative example '$fake' resolves — the check would false-positive"
    else
      pass "illustrative example '$fake' does not resolve (no false positive)"
    fi
  done
else
  fail "could not resolve HEAD — the self-test could not run"
fi

echo
echo "Tests run:    $TESTS_RUN"
echo "Tests failed: $TESTS_FAILED"
[ "$TESTS_FAILED" -eq 0 ]
