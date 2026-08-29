#!/usr/bin/env bash
# Smoke test for lib/clean-task-transients.sh
#
# Run: bash tests/state/clean-task-transients.sh
# Exits non-zero on any failure.
#
# Plugin-developer tooling only — not shipped to user projects.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
# shellcheck disable=SC1091
source "$REPO_ROOT/lib/clean-task-transients.sh"

TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT

TESTS_RUN=0
TESTS_FAILED=0

pass() {
  TESTS_RUN=$((TESTS_RUN + 1))
  echo "PASS: $1"
}

fail() {
  TESTS_RUN=$((TESTS_RUN + 1))
  TESTS_FAILED=$((TESTS_FAILED + 1))
  echo "FAIL: $1" >&2
}

# Build a representative planning task-dir with both transient and durable files.
seed_task_dir() {
  local d="$1"
  mkdir -p "$d"
  # T1 transients (must be removed)
  : > "$d/.kr-out.md"
  : > "$d/.ce-out.md"
  : > "$d/.tr-out.md"
  : > "$d/.spec-challenge-out.md"
  : > "$d/.research-out.md"
  : > "$d/.research-backend.md"          # per-facet
  : > "$d/.research-critique-approach-a.md"  # Phase 4 critique
  : > "$d/notes.md"
  : > "$d/ui-verify.png"
  : > "$d/playwright-verify.png"   # legacy name, still swept
  # T1.5 durables (must survive)
  printf 'spec\n'      > "$d/spec.md"
  printf 'state\n'     > "$d/state.md"
  printf 'plan\n'      > "$d/plan-v1.md"
  printf 'milestone\n' > "$d/milestone-1.md"
}

# Test 1: every documented transient is removed.
t1="$TMPDIR/task-clean"
seed_task_dir "$t1"
clean_task_transients "$t1"
leftover=$(find "$t1" -maxdepth 1 \( \
  -name '.kr-out.md' -o -name '.ce-out.md' -o -name '.tr-out.md' \
  -o -name '.spec-challenge-out.md' \
  -o -name '.research-*.md' -o -name 'notes.md' \
  -o -name 'ui-verify.png' -o -name 'playwright-verify.png' \
  \) 2>/dev/null)
if [ -z "$leftover" ]; then
  pass "clean_task_transients — removes all T1 transients (incl. per-facet + critique)"
else
  fail "clean_task_transients — left transients behind: $leftover"
fi

# Test 2: durable artifacts survive.
if [ -f "$t1/spec.md" ] && [ -f "$t1/state.md" ] && [ -f "$t1/plan-v1.md" ] && [ -f "$t1/milestone-1.md" ]; then
  pass "clean_task_transients — preserves T1.5 durables (spec/state/plan/milestone)"
else
  fail "clean_task_transients — deleted a durable artifact (dir now: $(ls "$t1"))"
fi

# Test 3: the task-dir itself is NOT removed (no rm -rf of the dir).
if [ -d "$t1" ]; then
  pass "clean_task_transients — leaves the task-dir in place"
else
  fail "clean_task_transients — removed the whole task-dir"
fi

# Test 4: missing dir is a silent no-op (rc 0), not an error.
set +e
clean_task_transients "$TMPDIR/does-not-exist"
rc=$?
set -e
if [ "$rc" -eq 0 ]; then
  pass "clean_task_transients — missing dir is a no-op (rc=0)"
else
  fail "clean_task_transients — missing dir returned rc=$rc (expected 0)"
fi

# Test 5: empty arg is a no-op (rc 0) — never operate on cwd.
sentinel="$TMPDIR/sentinel-cwd"
mkdir -p "$sentinel"
: > "$sentinel/.kr-out.md"
set +e
( cd "$sentinel" && clean_task_transients "" )
rc=$?
set -e
if [ "$rc" -eq 0 ] && [ -f "$sentinel/.kr-out.md" ]; then
  pass "clean_task_transients — empty arg is a no-op, never touches cwd"
else
  fail "clean_task_transients — empty arg mishandled (rc=$rc, file present=$([ -f "$sentinel/.kr-out.md" ] && echo yes || echo no))"
fi

# Test 5b: zero-arg call under `set -u` must reach the guard (rc=0), not abort on
# an unbound $1. Run in a subshell so an unfixed helper fails one assertion
# instead of crashing the suite.
set +e
rc=$(set -u; clean_task_transients >/dev/null 2>&1; echo $?)
set -e
if [ "$rc" -eq 0 ]; then
  pass "clean_task_transients — zero-arg under set -u returns 0 (not an unbound crash)"
else
  fail "clean_task_transients — zero-arg under set -u (rc=$rc, expected 0)"
fi

# Test 6: idempotent — second run on an already-clean dir is a no-op.
set +e
clean_task_transients "$t1"
rc=$?
set -e
if [ "$rc" -eq 0 ] && [ -f "$t1/spec.md" ]; then
  pass "clean_task_transients — idempotent on an already-clean dir"
else
  fail "clean_task_transients — second run not idempotent (rc=$rc)"
fi

# Test 7: direct CLI invocation works (BASH_SOURCE==0 entrypoint).
t7="$TMPDIR/task-cli"
seed_task_dir "$t7"
bash "$REPO_ROOT/lib/clean-task-transients.sh" "$t7"
if [ ! -f "$t7/.research-backend.md" ] && [ -f "$t7/spec.md" ]; then
  pass "clean-task-transients.sh — direct CLI invocation cleans transients, keeps durables"
else
  fail "clean-task-transients.sh — direct CLI invocation misbehaved"
fi

echo
echo "Tests run:    $TESTS_RUN"
echo "Tests failed: $TESTS_FAILED"
[ "$TESTS_FAILED" -eq 0 ]
