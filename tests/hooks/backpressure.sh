#!/usr/bin/env bash
# Smoke test for hooks/backpressure.sh run_silent — compresses passing command
# output and surfaces only failures (capped). The function had no coverage; pin
# the success/failure branches, the output cap + non-numeric-cap fallback, and the
# framework-summary extraction so a regression in any of them fails the suite.
#
# Run: bash tests/hooks/backpressure.sh

set -uo pipefail
REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"

TESTS_RUN=0
TESTS_FAILED=0
pass() { TESTS_RUN=$((TESTS_RUN + 1)); echo "PASS: $1"; }
fail() { TESTS_RUN=$((TESTS_RUN + 1)); TESTS_FAILED=$((TESTS_FAILED + 1)); echo "FAIL: $1" >&2; }

# shellcheck disable=SC1091
source "$REPO_ROOT/hooks/backpressure.sh"

# Success branch: exit 0 + "✓ ... passed"
set +e; out=$(run_silent "Unit" "true"); rc=$?; set -e
if [ "$rc" -eq 0 ] && printf '%s' "$out" | grep -q '✓ Unit passed'; then
  pass "success: returns 0 and prints a checkmark summary"
else
  fail "success branch — rc=$rc out='$out'"
fi

# Failure branch: propagates the command's non-zero exit + "✗ ... failed"
set +e; out=$(run_silent "Unit" "exit 3"); rc=$?; set -e
if [ "$rc" -eq 3 ] && printf '%s' "$out" | grep -q '✗ Unit failed (exit code 3)'; then
  pass "failure: propagates the exit code and prints the failure header"
else
  fail "failure branch — rc=$rc out='$out'"
fi

# Failure output is capped at GENIRO_BACKPRESSURE_CAP, with a truncation notice
GENIRO_BACKPRESSURE_CAP=5
set +e; out=$(run_silent "Big" "for i in \$(seq 1 50); do echo \"err line \$i\"; done; exit 1"); rc=$?; set -e
unset GENIRO_BACKPRESSURE_CAP
if [ "$rc" -eq 1 ] && printf '%s' "$out" | grep -q 'more lines truncated'; then
  pass "failure output is capped and reports a truncation notice"
else
  fail "cap branch — rc=$rc out='$out'"
fi

# Non-numeric cap falls back to the default without crashing
GENIRO_BACKPRESSURE_CAP=abc
set +e; out=$(run_silent "Bad cap" "echo hi"); rc=$?; set -e
unset GENIRO_BACKPRESSURE_CAP
if [ "$rc" -eq 0 ] && printf '%s' "$out" | grep -q '✓ Bad cap passed'; then
  pass "non-numeric GENIRO_BACKPRESSURE_CAP falls back to the default"
else
  fail "non-numeric cap fallback — rc=$rc out='$out'"
fi

# Framework summary extraction on success (pytest-style "===== N passed")
set +e; out=$(run_silent "Suite" "echo '===== 5 passed in 0.1s ====='"); rc=$?; set -e
if [ "$rc" -eq 0 ] && printf '%s' "$out" | grep -q '5 passed'; then
  pass "success summary extracts a framework test-count line"
else
  fail "summary extraction — rc=$rc out='$out'"
fi

# T1 #89 (2026-08-09 audit): the Go-summary `grep -c "^ok"` at :60 is a bare
# assignment with no pipe, so its rc is 1 on zero matches (grep -c's own exit
# code, even though it still prints "0") — a caller that sources this file
# under `set -e` must NOT abort on the SUCCESS path just because the output
# happened to contain no line starting with "ok". Run in a FRESH subshell with
# `set -e` active for the whole run_silent call (not toggled off around it, as
# the assertions above do) so the bug — an abort BEFORE the checkmark line
# ever prints — is what this test would catch.
set +e
out=$(bash -c '
  set -e
  source "'"$REPO_ROOT"'/hooks/backpressure.sh"
  run_silent "SetE" "echo hello"
' 2>&1)
rc=$?
set -e
if [ "$rc" -eq 0 ] && printf '%s' "$out" | grep -q '✓ SetE passed'; then
  pass "success path survives a sourcing caller's set -e with zero '^ok' lines"
else
  fail "set -e survival — rc=$rc out='$out'"
fi

# T1-8 (2026-08-23 audit): the two `grep -E ... | tail -1` summary assignments
# above the `grep -c "^ok"` line have the IDENTICAL bug under `pipefail`
# specifically (not plain `set -e`): a `grep` that finds no Jest/Vitest/pytest
# summary line exits 1, and under pipefail that makes the WHOLE `| tail -1`
# pipeline report 1 (tail itself always succeeds) — a bare assignment with
# that pipeline as its RHS then aborts a `set -e` caller on the SUCCESS path,
# before the checkmark line ever prints. This is the T1 #89 test above's
# shape but with `pipefail` added, and a command ("echo hello world") that
# deliberately produces neither a Jest/Vitest nor a pytest summary line, so
# BOTH `grep | tail` assignments miss and both must survive.
set +e
out=$(bash -c '
  set -euo pipefail
  source "'"$REPO_ROOT"'/hooks/backpressure.sh"
  run_silent "Tests" "echo hello world"
  echo "REACHED-NEXT-LINE"
' 2>&1)
rc=$?
set -e
if [ "$rc" -eq 0 ] && printf '%s' "$out" | grep -q '✓ Tests passed' && printf '%s' "$out" | grep -q 'REACHED-NEXT-LINE'; then
  pass "success path survives a sourcing caller's set -euo pipefail with no framework summary line"
else
  fail "pipefail survival (T1-8) — rc=$rc out='$out'"
fi

echo
echo "Tests run:    $TESTS_RUN"
echo "Tests failed: $TESTS_FAILED"
[ "$TESTS_FAILED" -eq 0 ]
