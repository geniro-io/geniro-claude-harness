#!/usr/bin/env bash
# T4-56 (plugin-audit 2026-10-19) — no shell suite exits with a failure COUNT as
# its status.
#
# Run: bash tests/authoring/lint-exit-count.sh
#
# Why this exists: a process exit status is one byte. `exit "$TESTS_FAILED"`
# exits 0 when exactly 256 assertions fail (and 1 when 257 do), so the one
# state a suite exists to report — "something failed" — reads as green. Three
# suites ended that way (tests/cursor/hook-shim.sh, tests/cursor/manifest-sync.sh,
# tests/authoring/lint-spawn-anchor.sh). The fix is `[ "$TESTS_FAILED" -eq 0 ]`
# as the last command, or `exit 1` behind an `if`.
#
# Detection: a line that is only `exit` plus a variable whose whole name is a
# failure counter (FAIL, FAILED, FAILS, FAILURES, ERRORS, with an optional
# TESTS_ prefix or _COUNT suffix), any case. A variable holding an exit CODE
# under another name (`rc`, `status`, `code`) never matches, so the common
# `exit "$rc"` stays legal.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$REPO_ROOT" || exit 1

FAILS=0
report_fail() { FAILS=$((FAILS + 1)); echo "FAIL: $1" >&2; }

COUNT_NAMES='(tests_)?(fail|failed|fails|failures|errors|nfail|nfailed)(_count)?'
EXIT_COUNT_PATTERN="^[[:space:]]*exit[[:space:]]+\"?\\\$\\{?${COUNT_NAMES}\\}?\"?[[:space:]]*(#.*)?\$"

# <paths...> -> `file:line:text` for every shell script that exits with a counter.
_hits() {
  grep -rniE --include='*.sh' -- "$EXIT_COUNT_PATTERN" "$@" 2>/dev/null
}

checked=0
while IFS= read -r hit; do
  [ -n "$hit" ] || continue
  checked=$((checked + 1))
  report_fail "${hit%%:*}:$(printf '%s' "${hit#*:}" | cut -d: -f1) — exits with a failure count, which wraps modulo 256 (256 failures exit 0); end with [ \"\$COUNT\" -eq 0 ] instead"
done < <(_hits tests scripts evals lib hooks)

if [ "$FAILS" -eq 0 ]; then
  echo "OK: no shell suite under tests/, scripts/, evals/, lib/ or hooks/ exits with a failure count"
fi

# --- self-test: red on each seeded counter spelling, green on exit codes and the fixed ending ----
SELFTEST_DIR="$(mktemp -d)"
trap 'rm -rf "$SELFTEST_DIR"' EXIT
mkdir -p "$SELFTEST_DIR/suites"

# Built with printf so this file never contains a line that matches its own pattern.
{
  printf 'exit "$%s"\n' TESTS_FAILED
  printf 'exit $%s\n' FAILS
  printf '  exit "${%s}"   # propagate\n' fail
} > "$SELFTEST_DIR/suites/violation.sh"
{
  printf 'exit "$%s"\n' rc
  printf 'exit $?\n'
  printf '[ "$%s" -eq 0 ]\n' TESTS_FAILED
  printf 'if [ "$%s" -gt 0 ]; then exit 1; fi\n' fail
  printf '# exit "$%s" in a comment\n' TESTS_FAILED
  printf 'exit "$%s"\n' fail_rc
} > "$SELFTEST_DIR/suites/clean.sh"

v=$(_hits "$SELFTEST_DIR/suites/violation.sh" | grep -c . || true)
if [ "$v" -eq 3 ]; then
  echo "OK: self-test — TESTS_FAILED, FAILS and a braced lower-case fail counter are all detected"
else
  report_fail "self-test — expected 3 seeded counter exits, got $v"
fi

c=$(_hits "$SELFTEST_DIR/suites/clean.sh" | grep -c . || true)
if [ "$c" -eq 0 ]; then
  echo "OK: self-test — exit codes (rc, \$?, fail_rc), the [ -eq 0 ] ending, an if/exit 1 and a comment do not false-positive"
else
  report_fail "self-test — the clean fixture false-positived ($c hit(s))"
fi

echo
if [ "$FAILS" -gt 0 ]; then
  echo "FAILED: $FAILS failure-count exit problem(s)." >&2
  exit 1
fi
echo "OK: no suite reports its result as a wrapping exit count."
