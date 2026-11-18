#!/usr/bin/env bash
# Tests for lib/unit-dir.sh (planning root, unit dir, handoff path).
#
# Run: bash tests/state/unit-dir.sh
# Exits non-zero on any failure. Temp git repos only.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
# shellcheck disable=SC1091
source "$REPO_ROOT/lib/unit-dir.sh"

TMPDIR_BASE="$(cd "$(mktemp -d)" && pwd -P)"
ORIGINAL_PWD="$PWD"
trap 'cd "$ORIGINAL_PWD"; rm -rf "$TMPDIR_BASE"' EXIT

TESTS_RUN=0
TESTS_FAILED=0
pass() { TESTS_RUN=$((TESTS_RUN + 1)); echo "PASS: $1"; }
fail() { TESTS_RUN=$((TESTS_RUN + 1)); TESTS_FAILED=$((TESTS_FAILED + 1)); echo "FAIL: $1" >&2; }
check() { # name got want
  if [ "$2" = "$3" ]; then pass "$1"; else fail "$1 (got '$2', want '$3')"; fi
}

# New repo with one commit on main; `.geniro/` gitignored unless $1 = tracked.
new_repo() {
  local d
  d="$(mktemp -d "$TMPDIR_BASE/repo.XXXXXX")"
  cd "$d" || return 1
  git init -q -b main
  [ "${1:-}" = tracked ] || printf '.geniro/\n' > .gitignore
  git add -A 2>/dev/null
  git -c user.email=t@t -c user.name=t commit -q --allow-empty -m init
  d="$(pwd -P)"
  PLAN="$d/.geniro/planning"
  mkdir -p "$PLAN"
  REPO="$d"
}

seed() { # <dir-name> <file> <branch>
  mkdir -p "$PLAN/$1"
  printf -- '---\ntier: T1\nbranch: %s\n---\nbody\n' "$3" > "$PLAN/$1/$2"
}

new_repo
git checkout -q -b feat/work
check "integration branch maps to its slug dir" "$(_geniro_unit_dir main)" "$PLAN/main"
check "master is an integration branch" "$(_geniro_unit_dir master)" "$PLAN/master"
seed some-task state.md '"feat/work"'
check "binding via state.md (quoted value)" "$(_geniro_unit_dir)" "$PLAN/some-task"

new_repo
git checkout -q -b feat/other
seed review-dir review.md feat/other
check "binding via review.md" "$(_geniro_unit_dir)" "$PLAN/review-dir"

new_repo
seed old-bind state.md feat/dup
seed new-bind debug.md feat/dup
touch -t 202001010000 "$PLAN/old-bind/state.md"
check "several bindings: newest wins" "$(_geniro_unit_dir feat/dup)" "$PLAN/new-bind"

new_repo
seed my-feature state.md main
check "plan dir with branch: main is unbound, matched by stripped name" "$(_geniro_unit_dir feat/my-feature)" "$PLAN/my-feature"
check "unbound dir also matched for a 3-segment branch via full slug only" "$(_geniro_unit_dir a/b/my-feature)" "$PLAN/a-b-my-feature"

new_repo
seed x state.md feat/x
check "feat/x lands in dir bound to it" "$(_geniro_unit_dir feat/x)" "$PLAN/x"
check "fix/x does not land in feat/x's dir" "$(_geniro_unit_dir fix/x)" "$PLAN/fix-x"

new_repo
mkdir -p "$PLAN/ci-1088-add-thing"
check "ticket match, one candidate" "$(_geniro_unit_dir feat/CI-1088-other-words)" "$PLAN/ci-1088-add-thing"
mkdir -p "$PLAN/ci-1088-second"
check "ticket match, two candidates falls through to name" "$(_geniro_unit_dir feat/CI-1088-other-words)" "$PLAN/ci-1088-other-words"

new_repo
check "fallback naming: two segments drop the prefix" "$(_geniro_unit_dir feat/new-thing)" "$PLAN/new-thing"
check "fallback naming: one segment keeps the slug" "$(_geniro_unit_dir solo)" "$PLAN/solo"
check "fallback naming: three segments keep the full slug" "$(_geniro_unit_dir a/b/c)" "$PLAN/a-b-c"
seed new-thing state.md fix/new-thing
check "fallback uses full slug when T is bound to another branch" "$(_geniro_unit_dir feat/new-thing)" "$PLAN/feat-new-thing"

new_repo
git checkout -q --detach
got="$(_geniro_unit_dir)"
case "$got" in
  "$PLAN"/detached-*) pass "detached HEAD maps to detached-<sha> dir" ;;
  *) fail "detached HEAD (got '$got')" ;;
esac

new_repo
git checkout -q -b feat/wt
wt="$TMPDIR_BASE/linked-ignored"
git worktree add -q "$wt" -b feat/in-wt
wt="$(cd "$wt" && pwd -P)"
check "planning root from linked worktree with .geniro ignored is the primary" "$(cd "$wt" && _geniro_planning_root)" "$REPO/.geniro/planning"
check "planning root from the primary itself" "$(_geniro_planning_root)" "$REPO/.geniro/planning"

new_repo tracked
wt="$TMPDIR_BASE/linked-tracked"
git worktree add -q "$wt" -b feat/in-wt
wt="$(cd "$wt" && pwd -P)"
check "planning root from linked worktree with tracked planning is its own toplevel" "$(cd "$wt" && _geniro_planning_root)" "$wt/.geniro/planning"

nogit="$(mktemp -d "$TMPDIR_BASE/nogit.XXXXXX")"
got="$(cd "$nogit" && _geniro_planning_root)"
check "non-git planning root falls back to the repo-root walk" "$got" "$(cd "$nogit" && _geniro_repo_root)/.geniro/planning"

new_repo
git checkout -q -b feat/hp
unit="$(_geniro_unit_dir)"
check "handoff path: neither exists -> unit path" "$(_geniro_handoff_path review)" "$unit/review.md"
mkdir -p "$REPO/.geniro/state/handoff"
: > "$REPO/.geniro/state/handoff/from-review-feat-hp.md"
check "handoff path: legacy only -> legacy path" "$(_geniro_handoff_path review)" "$REPO/.geniro/state/handoff/from-review-feat-hp.md"
mkdir -p "$unit"
: > "$unit/review.md"
check "handoff path: new exists -> new path" "$(_geniro_handoff_path review)" "$unit/review.md"
check "handoff path: explicit branch arg" "$(_geniro_handoff_path debug-adversarial feat/hp)" "$unit/debug-adversarial.md"

new_repo
git checkout -q -b feat/x
seed x debug.md feat/x
seed fix-null-crash state.md feat/x
touch -t 202001010000 "$PLAN/x/debug.md"
check "two dirs bound: debug handoff found in the older dir" "$(_geniro_handoff_path debug)" "$PLAN/x/debug.md"
check "two dirs bound: producer targets the dir holding debug.md" "$(_geniro_handoff_target debug)" "$PLAN/x/debug.md"
check "two dirs bound: unit dir is the newest bound" "$(_geniro_unit_dir)" "$PLAN/fix-null-crash"
check "two dirs bound: no review.md -> unit dir target" "$(_geniro_handoff_target review)" "$PLAN/fix-null-crash/review.md"
seed fix-null-crash review.md feat/x
touch -t 202001010000 "$PLAN/fix-null-crash/review.md"
seed x review.md feat/x
check "two dirs bound: newest review.md wins" "$(_geniro_handoff_target review)" "$PLAN/x/review.md"

new_repo
git checkout -q -b feat/tg
unit="$(_geniro_unit_dir)"
check "handoff target: nothing anywhere -> unit path" "$(_geniro_handoff_target debug)" "$unit/debug.md"
mkdir -p "$REPO/.geniro/state/handoff"
: > "$REPO/.geniro/state/handoff/from-debug-feat-tg.md"
check "handoff target: legacy only -> unit path" "$(_geniro_handoff_target debug)" "$unit/debug.md"
check "handoff path: legacy only -> legacy path" "$(_geniro_handoff_path debug)" "$REPO/.geniro/state/handoff/from-debug-feat-tg.md"

echo
echo "Tests run:    $TESTS_RUN"
echo "Tests failed: $TESTS_FAILED"
[ "$TESTS_FAILED" -eq 0 ]
