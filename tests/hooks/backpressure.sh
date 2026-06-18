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

echo
echo "Tests run:    $TESTS_RUN"
echo "Tests failed: $TESTS_FAILED"
[ "$TESTS_FAILED" -eq 0 ]
