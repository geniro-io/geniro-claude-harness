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

# Match with `grep -q PATTERN <<< "$var"`, never `printf '%s' "$var" | grep -q`.
# `grep -q` exits on its first match, so the producer can still be mid-write when
# the pipe closes; under `pipefail` that producer's SIGPIPE status becomes the
# pipeline's, and the assertion reads as FAILED on output it actually matched.
# A here-string is not a pipeline, so the shape cannot arise.
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
# Second scratch manifest, rewritten per case by the manifest-abuse section at the
# bottom. One file is enough: those cases are independent and never run in parallel.
_adv=$(mktemp) || exit 1
trap 'rm -f "$_fixture" "$_adv"' EXIT

# --- self-test: the stale-row detector fires -------------------------------
# One real path, one that cannot exist. A green run here means the tool has gone
# blind to deleted files, so every assertion below would be measuring nothing.
{
  printf 'FIX%sorchestrator%s1%sREADME.md\n' "$TAB" "$TAB" "$TAB"
  printf 'FIX%sorchestrator%s1%sskills/_shared/deleted-by-a-later-step.md\n' "$TAB" "$TAB" "$TAB"
} > "$_fixture"

out=$(GENIRO_RUN_LOAD_MANIFEST="$_fixture" "$SCRIPT" FIX 2>&1)
rc=$?
if [ "$rc" -ne 0 ] && grep -q 'deleted-by-a-later-step.md' <<< "$out"; then
  pass "self-test: a manifest row naming a missing file fails and names the path"
else
  fail "self-test: a missing path did not fail the run (rc=$rc) — the tool would report a load REDUCTION it caused itself"
fi

# A missing path must never be scored as zero words and folded into the total.
if grep -q 'MISSING' <<< "$out"; then
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
  if grep -q "^Profile $p$" <<< "$all"; then
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
if grep -q 'agents/reviewer-agent.md' <<< "$detail"; then
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

# --- rows the arithmetic cannot use ----------------------------------------
# Everything above measures a well-formed manifest. This section feeds the script
# rows it cannot honestly score, and the standard they are judged against is the
# one the script's own header sets: a row naming a file that no longer exists "is
# an error, not a zero ... it says the profile went stale rather than quietly
# reporting a smaller total." A row whose multiplier or profile field the script
# cannot use is wrong in the same direction and by the same mechanism — the number
# comes out smaller (or larger) than the run it claims to describe, and the report
# looks exactly as plausible either way. Silence is the defect, not the arithmetic.

# awk NF, not `wc -w`: GNU wc classifies words by locale, so a standalone `—` / `§`
# / `·` counts under C.UTF-8 and not under C, and the same file measures ~3% apart
# on two machines. awk splits on ASCII blanks only. Same rule as lint-skills.sh
# §words_in — a load figure and a size baseline that disagree are worse than either.
_words_in() { awk '{ w += NF } END { print w + 0 }' "$1"; }
README_WORDS=$(_words_in README.md)
CLAUDE_WORDS=$(_words_in CLAUDE.md)

# A profile name that is only a prefix of a real one is still an unknown profile.
# The guard is a substring match against the newline-joined profile list, so `R`
# matches the list containing `R1` and reaches the measurement path instead.
printf 'R1%sorchestrator%s1%sREADME.md\n' "$TAB" "$TAB" "$TAB" > "$_adv"
out=$(GENIRO_RUN_LOAD_MANIFEST="$_adv" "$SCRIPT" R 2>&1)
rc=$?
if [ "$rc" -eq 64 ]; then
  pass "a profile name that is only a prefix of a real one exits 64 like any unknown profile"
else
  fail "profile 'R' against a manifest holding only 'R1' exited $rc, expected 64 — a prefix slips past the substring guard and dies further in with the exit code a stale manifest uses, so a mistyped profile and a deleted file are indistinguishable to a caller. Output: $out"
fi

# The multiplier gate is `[ "$mult" -gt 1 ]`, with its diagnostic sent to
# /dev/null. Every value that is not an integer above 1 — a typo, a 0 meaning
# "not loaded", a negative — takes the same branch as a literal 1.
for _bad in x3 0 -2; do
  printf 'FIX%sagent-body%s%s%sREADME.md\n' "$TAB" "$TAB" "$_bad" "$TAB" > "$_adv"
  out=$(GENIRO_RUN_LOAD_MANIFEST="$_adv" "$SCRIPT" FIX 2>&1)
  rc=$?
  scored=$(printf '%s\n' "$out" | awk '$1 == "agent-body" { print $3 }')
  if [ "$rc" -ne 0 ] || grep -qiE 'multiplier|malformed|invalid' <<< "$out"; then
    pass "multiplier '$_bad' is surfaced instead of silently read as 1"
  else
    fail "multiplier '$_bad' scored the row at exactly 1x ($scored words, the file's own count is $README_WORDS) and exited 0 — the spawn multiplier is the one term this measurement exists to expose, so a value it cannot use has to fail the run the way a vanished path does"
  fi
done

# A multiplier bash cannot evaluate is worse than one it mis-reads: the
# arithmetic expansion fails, the echo never runs, and the row leaves no MISSING
# marker to trip the stale-row detector.
{ printf 'FIX%sorchestrator%s1%sREADME.md\n' "$TAB" "$TAB" "$TAB"
  printf 'FIX%sagent-body%s08%sCLAUDE.md\n' "$TAB" "$TAB" "$TAB"; } > "$_adv"
out=$(GENIRO_RUN_LOAD_MANIFEST="$_adv" "$SCRIPT" FIX 2>&1)
rc=$?
total=$(printf '%s\n' "$out" | awk '$1 == "total" { print $3 }')
if [ "$rc" -ne 0 ] || [ "${total:-0}" -ge "$((README_WORDS + CLAUDE_WORDS))" ]; then
  pass "a multiplier bash cannot evaluate does not silently remove its row from the total"
else
  fail "the row 'agent-body 08 CLAUDE.md' left the profile entirely: total $total accounts for README.md ($README_WORDS) alone, CLAUDE.md's $CLAUDE_WORDS words are nowhere, and the run exited 0. '08' is not a valid octal literal, so \$((words * mult)) fails and takes the whole echo with it"
fi

# A manifest with no data rows measures nothing. The suite above reads a 0 exit
# from --all as proof that every path in every profile resolves, so a manifest
# truncated by a bad edit — or an override pointing at the wrong file — must not
# clear that bar.
for _shape in "an empty" "a comments-only"; do
  if [ "$_shape" = "an empty" ]; then
    : > "$_adv"
  else
    printf '# profile\tcomponent\tmult\tpath\n' > "$_adv"
  fi
  out=$(GENIRO_RUN_LOAD_MANIFEST="$_adv" "$SCRIPT" --all 2>&1)
  rc=$?
  if [ "$rc" -ne 0 ] || [ -n "$out" ]; then
    pass "--all against $_shape manifest does not report success in total silence"
  else
    fail "--all exited 0 and printed nothing at all against $_shape manifest — a run that measured no profile at all is reported the same way as a clean one"
  fi
done

# Four tab-separated fields is what the hygiene check above verifies, and a row
# can satisfy it while naming no profile. `read` assigns the empty first field,
# the profile comparison never matches, and the row contributes to nothing.
{ printf 'FIX%sorchestrator%s1%sREADME.md\n' "$TAB" "$TAB" "$TAB"
  printf '%sagent-body%s1%sCLAUDE.md\n' "$TAB" "$TAB" "$TAB"; } > "$_adv"
out=$(GENIRO_RUN_LOAD_MANIFEST="$_adv" "$SCRIPT" --all 2>&1)
rc=$?
if [ "$rc" -ne 0 ] || grep -q 'CLAUDE.md' <<< "$out"; then
  pass "a row whose profile field is blank is surfaced rather than dropped from every profile"
else
  fail "the row with a blank profile field belongs to no profile: --all exited 0, and CLAUDE.md's $CLAUDE_WORDS words are in no report. The row carries four fields, so the four-field hygiene check passes it as well — nothing in the tool or the suite sees it"
fi

# Only a `#` in column 1 is stripped. An indented comment survives into the
# profile list, which is then expanded unquoted, so each of its words becomes a
# profile — including any real profile name the comment happens to mention.
{ printf 'R1%sorchestrator%s1%sREADME.md\n' "$TAB" "$TAB" "$TAB"
  printf '  # the R1 profile also loads the criteria files\n'; } > "$_adv"
out=$(GENIRO_RUN_LOAD_MANIFEST="$_adv" "$SCRIPT" --all 2>&1)
rc=$?
seen_r1=$(printf '%s\n' "$out" | grep -c '^Profile R1$' | tr -d '[:space:]')
if [ "$seen_r1" = "1" ]; then
  pass "--all reports each profile exactly once"
else
  fail "--all printed 'Profile R1' $seen_r1 times for a manifest holding one profile — the list is expanded unquoted (for p in \$profiles), and the indented comment mentions R1, so R1 is measured twice and a reader diffing two reports sees a doubled run"
fi
if grep -q "no manifest rows for profile 'the'" <<< "$out"; then
  fail "--all invented profiles from the words of an indented comment (\"no manifest rows for profile 'the'\") and exited $rc — a comment one space in is read as data"
else
  pass "an indented comment line is not read as profile data"
fi

echo
echo "Tests run:    $TESTS_RUN"
echo "Tests failed: $TESTS_FAILED"
[ "$TESTS_FAILED" -eq 0 ]
