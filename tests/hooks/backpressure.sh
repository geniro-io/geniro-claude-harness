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

# T4-62e: the FAILURE branch's own diagnostic filter pipe (grep -v | grep -v |
# grep -v | head, :88-91) has the identical pipefail exposure as the T1-8
# success-branch fix above, but on the failure path instead. A large output
# (200000 lines, all plain numbers — none match any noise pattern) makes
# `head -150` truncate and send SIGPIPE upstream; under `pipefail` that
# reports as a nonzero pipe exit even though `head` itself succeeded. Under a
# sourcing caller's `set -eo pipefail`, that nonzero would abort the whole
# shell at the pipe statement — before `return $exit_code` ever runs — so the
# function's real return value (3, from the wrapped command's own `exit 3`)
# is lost and replaced by whatever aborted the shell.
set +e
out=$(bash -c '
  set -eo pipefail
  source "'"$REPO_ROOT"'/hooks/backpressure.sh"
  run_silent "Big2" "seq 1 200000; exit 3" >/dev/null
  echo "REACHED-NEXT-LINE"
' 2>&1)
rc=$?
set -e
if [ "$rc" -eq 3 ] && ! printf '%s' "$out" | grep -q 'REACHED-NEXT-LINE'; then
  pass "failure branch survives a sourcing caller's set -eo pipefail — run_silent returns 3, not the filter pipe's incidental rc"
else
  fail "failure-branch pipefail survival (T4-62e) — rc=$rc out='$out'"
fi

# T4-53: a SIGINT/SIGTERM while the wrapped command runs must remove the capture
# file AND end the run with the signal's status (130 / 143). A trap that only
# cleaned up let the caller go on: run_silent printed a verdict for the
# interrupted command and the next line of the script ran. A stub mktemp puts the
# capture file in a directory the test can inspect (BSD mktemp ignores TMPDIR).
# `set -m` gives the background shell default signal dispositions, since a
# non-interactive shell starts background jobs with SIGINT ignored and an ignored
# signal cannot be trapped.
BP_CAP="$(mktemp -d)"; BP_BIN="$(mktemp -d)"; BP_MARK="$(mktemp -d)"
REAL_MKTEMP="$(command -v mktemp)"
printf '#!/bin/sh\nexec "%s" "%s/cap.XXXXXXXX"\n' "$REAL_MKTEMP" "$BP_CAP" > "$BP_BIN/mktemp"
chmod +x "$BP_BIN/mktemp"
# A suite that itself started with SIGINT ignored (tests/run-all.sh runs every
# suite as a background job) keeps it ignored in its children even under
# `set -m`, so no INT trap can fire there. Probe whether a job can receive
# SIGINT at all; where it cannot, the INT case is skipped and TERM still covers
# the trap's exit path.
set -m
bash -c 'trap "exit 7" INT; sleep 3' &
INT_PROBE=$!
set +m
sleep 0.3
kill -s INT "$INT_PROBE" 2>/dev/null || true
INT_PROBE_RC=0; wait "$INT_PROBE" 2>/dev/null || INT_PROBE_RC=$?
for SIG_CASE in "TERM 143" "INT 130"; do
  SIG="${SIG_CASE% *}"; WANT_RC="${SIG_CASE#* }"
  if [ "$SIG" = INT ] && [ "$INT_PROBE_RC" -ne 7 ]; then
    echo "SKIP: INT mid-run — this shell started with SIGINT ignored, so no job it spawns can trap SIGINT; the TERM case covers the trap"
    continue
  fi
  rm -f "$BP_MARK"/* "$BP_CAP"/*
  set -m
  PATH="$BP_BIN:$PATH" bash -c '
    source "$1/hooks/backpressure.sh"
    run_silent "Slow" "sleep 1"
    : > "$2/reached-next-line"
  ' _ "$REPO_ROOT" "$BP_MARK" >/dev/null 2>&1 &
  BP_PID=$!
  set +m
  for _ in $(seq 1 50); do [ -n "$(ls -A "$BP_CAP")" ] && break; sleep 0.1; done
  BP_HAD_CAPTURE="$(ls -A "$BP_CAP" | wc -l | tr -d ' ')"
  kill -s "$SIG" "$BP_PID" 2>/dev/null || true
  rc=0; wait "$BP_PID" 2>/dev/null || rc=$?
  if [ "$BP_HAD_CAPTURE" -eq 1 ] && [ "$rc" -eq "$WANT_RC" ] && [ ! -e "$BP_MARK/reached-next-line" ] && [ -z "$(ls -A "$BP_CAP")" ]; then
    pass "$SIG mid-run: capture file removed, run ends with $WANT_RC, caller's next line not reached"
  else
    fail "$SIG mid-run — captures-while-running=$BP_HAD_CAPTURE rc=$rc (want $WANT_RC) next-line-reached=$([ -e "$BP_MARK/reached-next-line" ] && echo yes || echo no) leftover=$(ls -A "$BP_CAP" | tr '\n' ' ')"
  fi
done
rm -rf "$BP_CAP" "$BP_BIN" "$BP_MARK"

echo
echo "Tests run:    $TESTS_RUN"
echo "Tests failed: $TESTS_FAILED"
[ "$TESTS_FAILED" -eq 0 ]
