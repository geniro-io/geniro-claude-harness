#!/usr/bin/env bash
# Smoke test for lib/branch-slug.sh — the single-source branch->slug derivation
# that session-start-restore and enforce-tdd-order must reproduce exactly. A drift
# in lowercase / collapse / truncate / trailing-dash handling computes a slug no
# producer ever wrote, so Tier-1 state resolution misses on long branches. Pin
# each rule so a derivation change fails the suite instead of silently breaking
# state resolution.
#
# Run: bash tests/memory/branch-slug.sh

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
source "$REPO_ROOT/lib/branch-slug.sh"

eq() { # eq <got> <want> <label>
  if [ "$1" = "$2" ]; then pass "$3"; else fail "$3 — got '$1' want '$2'"; fi
}

# lowercase + collapse a single separator
eq "$(_geniro_branch_slug 'Feature/Foo')" "feature-foo" "lowercases and collapses '/' to a dash"
# collapse every non-alnum run (slash, underscore, space) to one dash
eq "$(_geniro_branch_slug 'feat/CI-303_bar baz')" "feat-ci-303-bar-baz" "collapses every non-alnum run to a single dash"
eq "$(_geniro_branch_slug 'a//__  b')" "a-b" "adjacent separators collapse to one dash"
# strip leading/trailing dashes
eq "$(_geniro_branch_slug '/lead/trail/')" "lead-trail" "strips leading and trailing dashes"

# truncate to 60 chars
long_out="$(_geniro_branch_slug "$(printf 'a%.0s' {1..70})")"
if [ "${#long_out}" -eq 60 ]; then pass "truncates to 60 chars (got ${#long_out})"; else fail "truncate to 60 — got ${#long_out}"; fi

# strip a dash the 60-char truncation leaves at the boundary:
# 59 'a' + a separator lands the dash at index 59, so [0:60] ends in '-' -> stripped.
boundary_want="$(printf 'a%.0s' {1..59})"
eq "$(_geniro_branch_slug "$(printf 'a%.0s' {1..59}) x")" "$boundary_want" "strips a trailing dash left by truncation at the 60-char boundary"

# no-arg path derives the slug from the current git branch
sb="$(mktemp -d "$TMPDIR_BASE/repo.XXXXXX")"
( cd "$sb" && git init -q && git checkout -q -b 'Feature/Branch_Name' )
eq "$(cd "$sb" && _geniro_branch_slug)" "feature-branch-name" "no-arg path derives the slug from the current git branch"

echo
echo "Tests run:    $TESTS_RUN"
echo "Tests failed: $TESTS_FAILED"
[ "$TESTS_FAILED" -eq 0 ]
