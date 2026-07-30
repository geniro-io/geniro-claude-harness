#!/usr/bin/env bash
# Tests for scripts/measure-run-load.sh — the per-run load measurement.
#
# Two things here earn a test rather than a glance.
#
# The multiplier is the whole reason the script exists. Static size and per-run
# cost only diverge because an agent body is injected once per spawn, so a bug
# that dropped the multiplier would still print a plausible-looking table while
# erasing the single term the measurement was built to expose. A check that R2's
# agent-body term exceeds R1's pins that.
#
# And the stale-row failure is load-bearing, not cosmetic. Steps in the spec this
# script serves delete and rename files the manifest names; if a vanished path
# scored zero instead of failing, the tool would report a REDUCTION in per-run
# load caused entirely by its own blindness — the exact wrong answer, delivered
# confidently. So the detector is self-tested before anything else is trusted.
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/../.." || exit 1

TESTS_RUN=0
TESTS_FAILED=0
pass() { TESTS_RUN=$((TESTS_RUN + 1)); echo "PASS: $1"; }
fail() { TESTS_RUN=$((TESTS_RUN + 1)); TESTS_FAILED=$((TESTS_FAILED + 1)); echo "FAIL: $1"; }

SCRIPT=scripts/measure-run-load.sh
MANIFEST=scripts/run-load-profiles.tsv
TAB=$(printf '\t')

if [ ! -x "$SCRIPT" ]; then
  echo "FAIL: $SCRIPT is missing or not executable"
  exit 1
fi

_fixture=$(mktemp) || exit 1
trap 'rm -f "$_fixture"' EXIT

# --- self-test: the stale-row detector fires -------------------------------
# One real path, one that cannot exist. A green run here means the tool has gone
# blind to deleted files, so every assertion below would be measuring nothing.
{
  printf 'FIX%sorchestrator%s1%sREADME.md\n' "$TAB" "$TAB" "$TAB"
  printf 'FIX%sorchestrator%s1%sskills/_shared/deleted-by-a-later-step.md\n' "$TAB" "$TAB" "$TAB"
} > "$_fixture"

out=$(GENIRO_RUN_LOAD_MANIFEST="$_fixture" "$SCRIPT" FIX 2>&1)
rc=$?
if [ "$rc" -ne 0 ] && printf '%s' "$out" | grep -q 'deleted-by-a-later-step.md'; then
  pass "self-test: a manifest row naming a missing file fails and names the path"
else
  fail "self-test: a missing path did not fail the run (rc=$rc) — the tool would report a load REDUCTION it caused itself"
fi

# A missing path must never be scored as zero words and folded into the total.
if printf '%s' "$out" | grep -q 'MISSING'; then
  pass "self-test: the missing path is reported as MISSING rather than counted as zero"
else
  fail "self-test: MISSING row absent from the report — a vanished file may be silently scoring zero"
fi

# --- the real manifest measures cleanly ------------------------------------
all=$("$SCRIPT" --all 2>&1)
rc=$?
if [ "$rc" -eq 0 ]; then
  pass "--all exits 0 against the committed manifest"
else
  fail "--all exited $rc — every path in $MANIFEST must resolve. Output: $all"
fi

for p in R1 R2; do
  if printf '%s' "$all" | grep -q "^Profile $p$"; then
    pass "--all reports profile $p"
  else
    fail "--all does not report profile $p"
  fi
done

# --- component totals sum to the printed total -----------------------------
# Guards the arithmetic itself: a grouping bug that double-counted or dropped a
# component would still print a table, just a wrong one.
for p in R1 R2; do
  body=$("$SCRIPT" "$p" 2>/dev/null)
  summed=$(printf '%s\n' "$body" | awk '
    $1 == "orchestrator" || $1 == "criteria" || $1 == "agent-body" { s += $3 }
    END { print s + 0 }')
  printed=$(printf '%s\n' "$body" | awk '$1 == "total" { print $3 }')
  if [ -n "$printed" ] && [ "$summed" = "$printed" ]; then
    pass "$p component subtotals sum to the printed total ($printed words)"
  else
    fail "$p total mismatch — components sum to '$summed', report prints '$printed'"
  fi

  if [ "${printed:-0}" -gt 0 ]; then
    pass "$p reports a positive word total"
  else
    fail "$p reports a non-positive total ('$printed')"
  fi
done

# --- the spawn multiplier is actually applied ------------------------------
r1_body=$("$SCRIPT" R1 2>/dev/null | awk '$1 == "agent-body" { print $3 }')
r2_body=$("$SCRIPT" R2 2>/dev/null | awk '$1 == "agent-body" { print $3 }')
if [ -n "$r1_body" ] && [ -n "$r2_body" ] && [ "$r2_body" -gt "$r1_body" ]; then
  pass "agent-body scales with spawn count (R1 $r1_body < R2 $r2_body words)"
else
  fail "agent-body did not scale with spawn count (R1 '$r1_body', R2 '$r2_body') — the multiplier is the one term this measurement exists to expose"
fi

# The same body file backs both profiles, so an unapplied multiplier would make
# the two terms identical. Assert they are not.
if [ "$r1_body" != "$r2_body" ]; then
  pass "R1 and R2 agent-body terms differ, so the multiplier column is being read"
else
  fail "R1 and R2 agent-body terms are equal — the multiplier column looks ignored"
fi

# --- flags -----------------------------------------------------------------
if out=$("$SCRIPT" NoSuchProfile 2>&1); then
  fail "an unknown profile exited 0"
else
  rc=$?
  if [ "$rc" -eq 64 ]; then
    pass "an unknown profile exits 64 (EX_USAGE)"
  else
    fail "an unknown profile exited $rc, expected 64"
  fi
fi

if "$SCRIPT" >/dev/null 2>&1; then
  fail "no arguments exited 0 — usage should be an error"
else
  pass "no arguments is a usage error"
fi

detail=$("$SCRIPT" --detail R1 2>/dev/null)
if printf '%s' "$detail" | grep -q 'agents/reviewer-agent.md'; then
  pass "--detail names the individual files behind each component"
else
  fail "--detail did not list per-file rows"
fi

if [ "$(printf '%s\n' "$detail" | wc -l)" -gt "$(printf '%s\n' "$("$SCRIPT" R1 2>/dev/null)" | wc -l)" ]; then
  pass "--detail is longer than the summary it expands"
else
  fail "--detail produced no more output than the summary"
fi

# --- manifest hygiene ------------------------------------------------------
# Every non-comment row must carry all four tab-separated fields. A row short one
# field silently drops out of its profile, which reads as a smaller run.
malformed=$(grep -v '^#' "$MANIFEST" | grep -v '^[[:space:]]*$' \
  | awk -F"$TAB" 'NF != 4 { print NR ": " $0 }')
if [ -z "$malformed" ]; then
  pass "every manifest row carries four tab-separated fields"
else
  fail "malformed manifest rows: $malformed"
fi

echo
echo "Tests run:    $TESTS_RUN"
echo "Tests failed: $TESTS_FAILED"
[ "$TESTS_FAILED" -eq 0 ]
