#!/usr/bin/env bash
# Smoke test for skills/_shared/repo-root.sh.
#
# Run: bash tests/memory/repo-root.sh

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
TMPDIR_BASE="$(mktemp -d)"
ORIGINAL_PWD="$PWD"
trap 'cd "$ORIGINAL_PWD"; rm -rf "$TMPDIR_BASE"' EXIT

TESTS_RUN=0
TESTS_FAILED=0
pass() { TESTS_RUN=$((TESTS_RUN + 1)); echo "PASS: $1"; }
fail() { TESTS_RUN=$((TESTS_RUN + 1)); TESTS_FAILED=$((TESTS_FAILED + 1)); echo "FAIL: $1" >&2; }

# shellcheck disable=SC1091
source "$REPO_ROOT/skills/_shared/repo-root.sh"

# Helper: cd into a sandboxed dir, resolve root, assert. cd happens in the
# CURRENT shell so the test counters update correctly (subshells would lose
# them). Always cd back to TMPDIR_BASE at end to avoid bleed-over.
expect_root() {
  local from_dir="$1" expected="$2" label="$3"
  cd "$from_dir" || { fail "cd $from_dir failed"; return; }
  local got
  got=$(_geniro_repo_root)
  if [ "$got" = "$expected" ]; then
    pass "$label"
  else
    fail "$label — expected '$expected', got '$got'"
  fi
  cd "$TMPDIR_BASE"
}

# 1. Simple git project with .geniro/ at the root.
mkdir -p "$TMPDIR_BASE/proj1/.geniro"
( cd "$TMPDIR_BASE/proj1" && git init -q )
expect_root "$TMPDIR_BASE/proj1" "$TMPDIR_BASE/proj1" \
  "git toplevel + .geniro/ at root → resolves to root"

# 2. Submodule case — nested git repo inside the .geniro/-rooted project.
# Regression for round-3 P1: prior code preferred `git rev-parse --show-toplevel`
# which returned the INNER submodule path. The fix walks up for .geniro/ FIRST.
mkdir -p "$TMPDIR_BASE/proj2/.geniro"
( cd "$TMPDIR_BASE/proj2" && git init -q )
mkdir -p "$TMPDIR_BASE/proj2/.geniro/vendor/lib"
( cd "$TMPDIR_BASE/proj2/.geniro/vendor/lib" && git init -q )
expect_root "$TMPDIR_BASE/proj2/.geniro/vendor/lib" "$TMPDIR_BASE/proj2" \
  "submodule under .geniro/ resolves to OUTER project (walk-up beats git toplevel)"

# 3. Fresh-install — git repo without .geniro/ yet. Falls back to git toplevel.
mkdir -p "$TMPDIR_BASE/proj3/src"
( cd "$TMPDIR_BASE/proj3" && git init -q )
expect_root "$TMPDIR_BASE/proj3/src" "$TMPDIR_BASE/proj3" \
  "git repo without .geniro/ falls back to git toplevel"

# 4. No git, no .geniro/ — last-resort fallback is $PWD.
mkdir -p "$TMPDIR_BASE/no-git-no-geniro"
expect_root "$TMPDIR_BASE/no-git-no-geniro" "$TMPDIR_BASE/no-git-no-geniro" \
  "no git + no .geniro/ → \$PWD as last resort"

# 5. Walk-up from deeply nested cwd.
mkdir -p "$TMPDIR_BASE/proj4/.geniro"
mkdir -p "$TMPDIR_BASE/proj4/a/b/c/d"
( cd "$TMPDIR_BASE/proj4" && git init -q )
expect_root "$TMPDIR_BASE/proj4/a/b/c/d" "$TMPDIR_BASE/proj4" \
  "walk-up from deeply nested cwd finds .geniro/ ancestor"

# 6. Walk-up from INSIDE .geniro/ finds the parent.
mkdir -p "$TMPDIR_BASE/proj5/.geniro/state/foo"
( cd "$TMPDIR_BASE/proj5" && git init -q )
expect_root "$TMPDIR_BASE/proj5/.geniro/state/foo" "$TMPDIR_BASE/proj5" \
  "walk-up from inside .geniro/ finds the parent containing .geniro/"

echo
echo "Tests run:    $TESTS_RUN"
echo "Tests failed: $TESTS_FAILED"
[ "$TESTS_FAILED" -eq 0 ]
