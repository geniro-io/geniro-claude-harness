#!/usr/bin/env bash
# Smoke test for lib/repo-root.sh.
#
# Run: bash tests/memory/repo-root.sh

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
TMPDIR_BASE="$(cd "$(mktemp -d)" && pwd -P)"
ORIGINAL_PWD="$PWD"
trap 'cd "$ORIGINAL_PWD"; rm -rf "$TMPDIR_BASE"' EXIT

TESTS_RUN=0
TESTS_FAILED=0
pass() { TESTS_RUN=$((TESTS_RUN + 1)); echo "PASS: $1"; }
fail() { TESTS_RUN=$((TESTS_RUN + 1)); TESTS_FAILED=$((TESTS_FAILED + 1)); echo "FAIL: $1" >&2; }

# shellcheck disable=SC1091
source "$REPO_ROOT/lib/repo-root.sh"

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
  cd "$TMPDIR_BASE" || exit
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

# 7. Linked worktree of a NORMAL repo resolves to the primary worktree —
# cross-session memory writes must land in primary, not the removable linked
# worktree.
mkdir -p "$TMPDIR_BASE/proj6/.geniro"
( cd "$TMPDIR_BASE/proj6" && git init -q \
  && git -c user.email=t@t -c user.name=t commit -q --allow-empty -m init \
  && git worktree add -q "$TMPDIR_BASE/proj6-wt" 2>/dev/null )
expect_root "$TMPDIR_BASE/proj6-wt" "$TMPDIR_BASE/proj6" \
  "linked worktree of a normal repo resolves to the primary worktree"

# 8. Standalone bare repo: the bare dir itself is main (it has no checkout);
# the worktree's own path is never main.
mkdir -p "$TMPDIR_BASE/bare-src"
( cd "$TMPDIR_BASE/bare-src" && git init -q \
  && git -c user.email=t@t -c user.name=t commit -q --allow-empty -m init )
git clone -q --bare "$TMPDIR_BASE/bare-src" "$TMPDIR_BASE/hub.git" 2>/dev/null
( cd "$TMPDIR_BASE/hub.git" && git worktree add -q "$TMPDIR_BASE/wt-of-bare" 2>/dev/null )
expect_root "$TMPDIR_BASE/wt-of-bare" "$TMPDIR_BASE/hub.git" \
  "worktree of a standalone bare repo resolves to the bare dir"

# 9. Bare-hub layout (<hub>/.bare + <hub>/.git file): main is <hub> from every
# worktree and from the hub root, and a worktree that sorts first does not
# move it.
mkdir -p "$TMPDIR_BASE/hub"
git clone -q --bare "$TMPDIR_BASE/bare-src" "$TMPDIR_BASE/hub/.bare" 2>/dev/null
printf 'gitdir: ./.bare\n' > "$TMPDIR_BASE/hub/.git"
( cd "$TMPDIR_BASE/hub" \
  && git worktree add -q "$TMPDIR_BASE/hub/zz-feature" -b zz-feature 2>/dev/null \
  && git worktree add -q "$TMPDIR_BASE/hub/aa-main" -b aa-main 2>/dev/null )
expect_root "$TMPDIR_BASE/hub/zz-feature" "$TMPDIR_BASE/hub" "bare hub: from zz-feature resolves to <hub>"
expect_root "$TMPDIR_BASE/hub/aa-main" "$TMPDIR_BASE/hub" "bare hub: from aa-main resolves to <hub>"
expect_root "$TMPDIR_BASE/hub" "$TMPDIR_BASE/hub" "bare hub: from the hub root resolves to <hub>"
( cd "$TMPDIR_BASE/hub" && git worktree add -q "$TMPDIR_BASE/hub/01-hotfix" -b 01-hotfix 2>/dev/null )
expect_root "$TMPDIR_BASE/hub/zz-feature" "$TMPDIR_BASE/hub" "bare hub: a worktree sorting first does not move the root"

# 10. Normal repo: linked worktrees inside .claude/worktrees/ and outside the
# repo (path with a space) resolve to main, with or without a .geniro/ of their own.
mkdir -p "$TMPDIR_BASE/proj7"
( cd "$TMPDIR_BASE/proj7" && git init -q \
  && git -c user.email=t@t -c user.name=t commit -q --allow-empty -m init \
  && git worktree add -q "$TMPDIR_BASE/proj7/.claude/worktrees/inside" -b inside 2>/dev/null \
  && git worktree add -q "$TMPDIR_BASE/outside dir/wt" -b outside 2>/dev/null )
mkdir -p "$TMPDIR_BASE/proj7/.claude/worktrees/inside/.geniro" "$TMPDIR_BASE/outside dir/wt/sub"
expect_root "$TMPDIR_BASE/proj7/.claude/worktrees/inside" "$TMPDIR_BASE/proj7" \
  "worktree under .claude/worktrees resolves to main despite its own .geniro/"
expect_root "$TMPDIR_BASE/outside dir/wt/sub" "$TMPDIR_BASE/proj7" \
  "subdir of a worktree outside the repo (space in path) resolves to main"
expect_root "$TMPDIR_BASE/proj7" "$TMPDIR_BASE/proj7" "main checkout without .geniro/ resolves to itself"

# 11. Real submodule (common dir under <super>/.git/modules/, core.worktree set):
# its main checkout is the submodule checkout itself, never a path inside .git.
mkdir -p "$TMPDIR_BASE/super"
( cd "$TMPDIR_BASE/super" && git init -q \
  && git -c user.email=t@t -c user.name=t commit -q --allow-empty -m init \
  && git -c protocol.file.allow=always -c user.email=t@t -c user.name=t \
       submodule add -q "$TMPDIR_BASE/bare-src" sub 2>/dev/null )
expect_root "$TMPDIR_BASE/super/sub" "$TMPDIR_BASE/super/sub" "submodule resolves to its own checkout, not <super>/.git/modules"
mkdir -p "$TMPDIR_BASE/super/.geniro"
expect_root "$TMPDIR_BASE/super/sub" "$TMPDIR_BASE/super" "submodule without .geniro/ walks up to the superproject's"
# A linked worktree of the submodule resolves like the submodule checkout itself.
( cd "$TMPDIR_BASE/super/sub" && git -c user.email=t@t -c user.name=t worktree add -q "$TMPDIR_BASE/sub-wt" -b subwt 2>/dev/null )
expect_root "$TMPDIR_BASE/sub-wt" "$TMPDIR_BASE/super" "submodule linked worktree resolves to the superproject's .geniro/ like the submodule itself"
rm -rf "$TMPDIR_BASE/super/.geniro"
expect_root "$TMPDIR_BASE/sub-wt" "$TMPDIR_BASE/super/sub" "submodule linked worktree without any .geniro/ resolves to the submodule checkout"

# 11b. --separate-git-dir: git lists the git dir as the main worktree; never return it.
mkdir -p "$TMPDIR_BASE/sep"
git init -q --separate-git-dir "$TMPDIR_BASE/sep-gitdir" "$TMPDIR_BASE/sep"
expect_root "$TMPDIR_BASE/sep" "$TMPDIR_BASE/sep" "separate-git-dir checkout resolves to itself, not the git dir"

# 12. Main checkout moved after a worktree was made: git fails in the worktree;
# stdout is still the fallback path, stderr names the stale main, rc 0.
mkdir -p "$TMPDIR_BASE/movable"
( cd "$TMPDIR_BASE/movable" && git init -q \
  && git -c user.email=t@t -c user.name=t commit -q --allow-empty -m init \
  && git worktree add -q "$TMPDIR_BASE/movable-wt" -b wt 2>/dev/null )
mv "$TMPDIR_BASE/movable" "$TMPDIR_BASE/movable-renamed"
cd "$TMPDIR_BASE/movable-wt" || exit 1
got=$(_geniro_repo_root 2>"$TMPDIR_BASE/stderr.txt"); rc=$?
if [ "$rc" -eq 0 ] && [ "$got" = "$TMPDIR_BASE/movable-wt" ]; then
  pass "moved main: stdout is the fallback path, rc 0"
else
  fail "moved main: expected '$TMPDIR_BASE/movable-wt' rc 0, got '$got' rc $rc"
fi
if grep -q "main checkout is missing at $TMPDIR_BASE/movable " "$TMPDIR_BASE/stderr.txt" \
   && grep -q "git worktree repair $TMPDIR_BASE/movable-wt" "$TMPDIR_BASE/stderr.txt"; then
  pass "moved main: stderr names the stale path and the fix"
else
  fail "moved main: stderr was '$(cat "$TMPDIR_BASE/stderr.txt")'"
fi
if [ "$(wc -l < "$TMPDIR_BASE/stderr.txt" | tr -d ' ')" -eq 1 ]; then
  pass "moved main: exactly one stderr line"
else
  fail "moved main: stderr not one line"
fi
cd "$TMPDIR_BASE" || exit 1

echo
echo "Tests run:    $TESTS_RUN"
echo "Tests failed: $TESTS_FAILED"
[ "$TESTS_FAILED" -eq 0 ]
