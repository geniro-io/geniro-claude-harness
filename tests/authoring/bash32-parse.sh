#!/usr/bin/env bash
# bash 3.2 parse check for hooks/ and lib/.
#
# macOS ships bash 3.2 as /bin/bash, and 3.2 parses one construct differently
# from 5.x: it does not skip comments while scanning a `$( )` body, so an
# apostrophe inside a comment inside a command substitution reads as an
# unterminated quote and the whole file fails to parse. The script then dies at
# run time on a Mac while every other check says it is fine — ShellCheck does
# not model it, and `bash -n` under 5.x accepts it.
#
# The check has to run under a real 3.2-era parser, which is why it lives here
# and not in CI: the GitHub runner is Linux with bash 5, so a CI step would pass
# unconditionally and give false assurance about the exact class it exists to
# catch. On a developer Mac /bin/bash IS 3.2 and this suite is meaningful.
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/../.." || exit 1

TESTS_RUN=0
TESTS_FAILED=0
pass() { TESTS_RUN=$((TESTS_RUN + 1)); echo "PASS: $1"; }
fail() { TESTS_RUN=$((TESTS_RUN + 1)); TESTS_FAILED=$((TESTS_FAILED + 1)); echo "FAIL: $1"; }

SYS_BASH=/bin/bash
if [ ! -x "$SYS_BASH" ]; then
  echo "SKIP: no $SYS_BASH on this platform"
  exit 0
fi

ver=$("$SYS_BASH" -c 'echo "${BASH_VERSINFO[0]}"' 2>/dev/null || echo 0)
if [ "$ver" -ge 4 ]; then
  # Report the skip loudly rather than printing a green tick: a silent pass here
  # would read as "the 3.2 class is covered" on a machine that cannot check it.
  echo "SKIP: $SYS_BASH is bash $ver, not 3.x — this check needs a 3.2-era parser"
  echo "      (expected on Linux/CI; the class is only reachable on macOS)"
  exit 0
fi

# Self-test first. A parse check that has quietly stopped detecting its target
# reports 26 green ticks and means nothing, so prove the detector fires on a
# known-bad shape before trusting the sweep. The shape needs the command
# substitution inside DOUBLE QUOTES — bare `$( )` with the same comment parses
# fine even on 3.2, which is why this fixture is exact rather than approximate.
_probe=$(mktemp) || exit 1
trap 'rm -f "$_probe"' EXIT
printf '%s\n' 'x="$(' '  # every caller'"'"'s view' '  echo hi' ')"' > "$_probe"
if "$SYS_BASH" -n "$_probe" 2>/dev/null; then
  fail "self-test: $SYS_BASH accepted the known-bad comment-in-\$() shape — this check is blind, fix it before trusting the results below"
else
  pass "self-test: detector fires on the known-bad comment-in-\$() shape"
fi

for f in $(find hooks lib -name '*.sh' -type f | sort); do
  if err=$("$SYS_BASH" -n "$f" 2>&1); then
    pass "bash $ver parses $f"
  else
    fail "bash $ver cannot parse $f — $err"
  fi
done

echo
echo "Tests run:    $TESTS_RUN"
echo "Tests failed: $TESTS_FAILED"
[ "$TESTS_FAILED" -eq 0 ]
