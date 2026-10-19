#!/usr/bin/env bash
# Runs scripts/word-delta.sh against a scratch git repo and checks its exit status
# and total: growth fails, shrink and no-change pass, untracked files count, and
# files outside the instruction scope are ignored.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
TESTS_RUN=0
TESTS_FAILED=0
pass() { TESTS_RUN=$((TESTS_RUN + 1)); echo "PASS: $1"; }
fail() { TESTS_RUN=$((TESTS_RUN + 1)); TESTS_FAILED=$((TESTS_FAILED + 1)); echo "FAIL: $1"; }

T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT
cd "$T" || exit 1
git init -q
git config user.email t@example.com
git config user.name t
mkdir -p scripts skills/a agents lib
cp "$REPO_ROOT/scripts/word-delta.sh" scripts/
printf 'one two three four\n' > skills/a/SKILL.md
printf 'alpha beta\n' > agents/x.md
printf 'echo code\n' > lib/x.sh
git add -A && git commit -qm base
BASE="$(git rev-parse HEAD)"

out="$(bash scripts/word-delta.sh "$BASE")"; rc=$?
[ "$rc" -eq 0 ] && echo "$out" | grep -q '^ *+0  total' \
  && pass "no change: total +0, exit 0" || fail "no change: rc=$rc out=$out"

printf 'one two\n' > skills/a/SKILL.md
out="$(bash scripts/word-delta.sh "$BASE")"; rc=$?
[ "$rc" -eq 0 ] && echo "$out" | grep -q '^ *-2  total' \
  && pass "shrink: total -2, exit 0" || fail "shrink: rc=$rc out=$out"

printf 'gamma delta epsilon\n' > skills/a/new-reference.md
out="$(bash scripts/word-delta.sh "$BASE")"; rc=$?
[ "$rc" -eq 1 ] && echo "$out" | grep -q '^ *+1  total' \
  && pass "untracked file counts: -2 + 3 = +1, exit 1" || fail "untracked: rc=$rc out=$out"

rm skills/a/new-reference.md
printf 'echo code and a great deal more prose that is not instructions\n' > lib/x.sh
out="$(bash scripts/word-delta.sh "$BASE")"; rc=$?
[ "$rc" -eq 0 ] && ! echo "$out" | grep -q 'lib/x.sh' \
  && pass "files outside the instruction scope are ignored" || fail "scope: rc=$rc out=$out"

out="$(bash scripts/word-delta.sh no-such-ref 2>&1)"; rc=$?
[ "$rc" -eq 2 ] && pass "unresolvable base: exit 2" || fail "bad base: rc=$rc out=$out"

echo
echo "Tests run:    $TESTS_RUN"
echo "Tests failed: $TESTS_FAILED"
[ "$TESTS_FAILED" -eq 0 ]
