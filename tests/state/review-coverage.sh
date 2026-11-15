#!/usr/bin/env bash
# Behavior test for lib/review-coverage.sh on scratch git repos.
#
# Run: bash tests/state/review-coverage.sh
# Exits non-zero on any failure.
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
# shellcheck disable=SC1091
source "$REPO_ROOT/lib/review-coverage.sh"

TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT

TESTS_RUN=0
TESTS_FAILED=0
pass() { TESTS_RUN=$((TESTS_RUN + 1)); echo "PASS: $1"; }
fail() { TESTS_RUN=$((TESTS_RUN + 1)); TESTS_FAILED=$((TESTS_FAILED + 1)); echo "FAIL: $1"; }

# expect <name> <want-rc> <want-output> <state> [files...]
expect() {
  _name="$1"; _wrc="$2"; _wout="$3"; shift 3
  _out=$(review_coverage_diverged "$@" 2>/dev/null); _rc=$?
  if [ "$_rc" = "$_wrc" ] && [ "$_out" = "$_wout" ]; then pass "$_name"
  else fail "$_name (rc=$_rc want $_wrc; out=[$_out] want [$_wout])"; fi
}

REPO="$TMPDIR/repo"
mkdir -p "$REPO/src"
cd "$REPO" || exit 1
git init -q .
echo a > src/a.txt
echo b > src/b.txt
ha=$(git hash-object src/a.txt)
hb=$(git hash-object src/b.txt)

state() { # state <path> <set-lines> <hash-lines>
  printf -- '---\nphase: ship\n%s\n%s\nother: x\n---\nbody\n' "$2" "$3" > "$1"
}
TAB=$(printf '\t')

state s_flow "reviewed_file_set: [src/a.txt, src/b.txt]" "reviewed_file_hashes: [src/a.txt@$ha, src/b.txt@$hb]"
expect "flow form, equal sets and hashes -> rc 0" 0 "" s_flow src/a.txt src/b.txt
expect "no changed files, hashes intact -> rc 0" 0 "" s_flow
expect "subset of reviewed files changed -> rc 0" 0 "" s_flow src/a.txt

state s_block "reviewed_file_set:
  - src/a.txt
  - src/b.txt" "reviewed_file_hashes:
  - src/a.txt@$ha
  - \"src/b.txt@$hb\""
expect "block form, equal -> rc 0" 0 "" s_block src/a.txt src/b.txt

echo c > src/c.txt
expect "unreviewed changed file listed -> rc 1" 1 "src/c.txt${TAB}unreviewed" s_flow src/a.txt src/c.txt

echo edited >> src/a.txt
expect "edited reviewed file listed -> rc 1" 1 "src/a.txt${TAB}modified" s_flow src/a.txt
expect "edited reviewed file listed even when not in changed args" 1 "src/a.txt${TAB}modified" s_flow
echo a > src/a.txt
expect "restored content matches again -> rc 0" 0 "" s_flow src/a.txt

rm src/b.txt
expect "deleted reviewed file listed -> rc 1" 1 "src/b.txt${TAB}deleted" s_flow src/b.txt
echo b > src/b.txt

state s_empty "reviewed_file_set: []" "reviewed_file_hashes: []"
expect "empty reviewed set, no changes -> rc 0" 0 "" s_empty
expect "empty reviewed set, changed file -> unreviewed" 1 "src/a.txt${TAB}unreviewed" s_empty src/a.txt

state s_nohash "reviewed_file_set: [src/a.txt, src/b.txt]" "reviewed_file_hashes: [src/a.txt@$ha]"
expect "reviewed file without a hash entry listed" 1 "src/b.txt${TAB}nohash" s_nohash src/a.txt src/b.txt

printf 'no frontmatter here\n' > s_bad1
expect "no frontmatter -> rc 2" 2 "" s_bad1 src/a.txt
state s_bad2 "reviewed_file_set: src/a.txt" "reviewed_file_hashes: []"
expect "scalar instead of list -> rc 2" 2 "" s_bad2 src/a.txt
printf -- '---\nreviewed_file_set: []\n---\n' > s_bad3
expect "missing hashes key -> rc 2" 2 "" s_bad3
expect "missing state file -> rc 2" 2 "" "$TMPDIR/nope.md"
expect "no arguments -> rc 2" 2 ""

echo
echo "Tests run:    $TESTS_RUN"
echo "Tests failed: $TESTS_FAILED"
[ "$TESTS_FAILED" -eq 0 ]
