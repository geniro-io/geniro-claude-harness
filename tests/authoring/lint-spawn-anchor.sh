#!/usr/bin/env bash
# Guards the subagent spawn anchor's re-anchoring form.
#
# Run: bash tests/authoring/lint-spawn-anchor.sh
#
# Why this exists: the anchor used to tell a subagent to compare its INHERITED
# cwd against WORKTREE and abort on a mismatch. That holds only under Claude
# Code, which passes the parent's cwd down. Cursor starts a subagent at the
# workspace root, so every anchored spawn fired from a linked worktree or a PR
# head aborted on its first Bash call and the run reported "no review was
# performed" — with the target tree reachable the whole time.
#
# The fix is directional: WORKTREE is absolute, so the subagent `cd`s to it
# instead of asserting it already arrived there. This suite fails if an
# assert-and-abort anchor comes back into a spawn prompt.
#
# Coverage:
#   - No spawn prompt carries the old assert-on-inherited-cwd anchor.
#   - Every spawn prompt that names a WORKTREE slot also carries the `cd` form.
#   - scope-anchor.md still documents the canonical template.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$REPO_ROOT" || exit 1

CANON="skills/_shared/scope-anchor.md"

TESTS_RUN=0
TESTS_FAILED=0
pass() { TESTS_RUN=$((TESTS_RUN + 1)); echo "PASS: $1"; }
fail() { TESTS_RUN=$((TESTS_RUN + 1)); TESTS_FAILED=$((TESTS_FAILED + 1)); echo "FAIL: $1" >&2; }

# --- 1. the assert-and-abort form is gone from every subagent anchor ---------
#
# The orchestrator-side variant is exempt and matched separately below: an
# orchestrator IS the session, so its own cwd is authoritative by
# scope-anchor.md § The rule and cannot drift.
offenders="$(grep -rn 'stay within WORKTREE on BRANCH' --include='*.md' skills \
  | grep -v 'orchestrator verifies' || true)"
if [ -z "$offenders" ]; then
  pass "no spawn prompt asserts an inherited cwd against WORKTREE"
else
  fail "assert-and-abort anchor found — a subagent under a runtime that does not inherit cwd aborts instead of re-anchoring:"
  printf '  %s\n' "$offenders" >&2
fi

# --- 2. every WORKTREE-slot spawn prompt re-anchors with cd ------------------
#
# A file that hands a subagent a WORKTREE slot but never tells it to cd there
# is the same bug wearing a different sentence.
missing=""
while IFS= read -r f; do
  [ -n "$f" ] || continue
  grep -qF 'cd <WORKTREE> &&' "$f" || missing="$missing$f"$'\n'
done < <(grep -rl '^WORKTREE:' --include='*.md' skills | sort)

if [ -z "$missing" ]; then
  pass "every WORKTREE-slot spawn prompt re-anchors with cd"
else
  fail "spawn prompt declares a WORKTREE slot but never cds into it:"
  printf '  %s\n' "$missing" >&2
fi

# --- 3. the canonical template still carries the rule -----------------------
# Copies are derived from this block; if it regresses, the next author
# propagates the regression outward.
if grep -qF 'cd <WORKTREE> && pwd && git branch --show-current' "$CANON"; then
  pass "$CANON documents the canonical re-anchoring template"
else
  fail "$CANON no longer carries the canonical re-anchoring template"
fi

echo
echo "Tests run: $TESTS_RUN, failed: $TESTS_FAILED"
exit "$TESTS_FAILED"
