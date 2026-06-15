#!/usr/bin/env bash
# Smoke test for lib/archive-stale.sh
#
# Run: bash tests/memory/archive-stale.sh
#
# Coverage:
#   - No learnings.jsonl -> rc=1 (informational, nothing to archive).
#   - Stale entry (score<0.1 AND age>180d AND access_count==0 AND not-deprecated)
#     flipped to deprecated:true.
#   - Fresh / accessed / already-deprecated entries are NOT (re)flipped.
#   - Never deletes: line count is preserved across a real run.
#   - --dry-run reports but does NOT write.
#   - Malformed line -> refuse rewrite (rc=2), file left intact (audit trail).
#   - Non-numeric GENIRO_DECAY_TAU_DAYS -> rc=2.
#   - Verification-coverage line: verified/total over the live (non-deprecated)
#     set, present on the report; n/a on an empty corpus; printed even when 0
#     entries are stale.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"

TMPDIR_BASE="$(mktemp -d)"
ORIGINAL_PWD="$PWD"
trap 'cd "$ORIGINAL_PWD"; rm -rf "$TMPDIR_BASE"' EXIT

TESTS_RUN=0
TESTS_FAILED=0
pass() { TESTS_RUN=$((TESTS_RUN + 1)); echo "PASS: $1"; }
fail() { TESTS_RUN=$((TESTS_RUN + 1)); TESTS_FAILED=$((TESTS_FAILED + 1)); echo "FAIL: $1" >&2; }

LOG=""
new_sandbox() {
  local d; d="$(mktemp -d "$TMPDIR_BASE/sandbox.XXXXXXXXXX")"
  mkdir -p "$d/.geniro/knowledge"
  cd "$d" || return 1
  git init -q
  LOG="$d/.geniro/knowledge/learnings.jsonl"
  # shellcheck disable=SC1091
  source "$REPO_ROOT/lib/archive-stale.sh"
}

# Read the `deprecated` field of the entry with a given dedup_key.
dep_of() { jq -r --arg k "$1" 'select(.dedup_key==$k) | (.deprecated // false)' "$LOG"; }
line_count() { if [ -f "$LOG" ]; then wc -l < "$LOG" | tr -d ' '; else echo 0; fi; }

NOW_TS="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

# A canonical four-entry corpus: one genuinely stale, plus three controls that
# each fail exactly one staleness criterion (recency / access / already-flipped).
write_corpus() {
  {
    printf '%s\n' '{"producer":"/debug","scope":"x","summary":"stale one","tags":["bug"],"type":"diagnosis","ts":"2020-01-01T00:00:00Z","trust":"inferred","access_count":0,"recurrence_count":1,"dedup_key":"stale1"}'
    printf '{"producer":"/debug","scope":"x","summary":"fresh one","tags":["bug"],"type":"diagnosis","ts":"%s","trust":"verified","access_count":0,"recurrence_count":1,"dedup_key":"fresh1"}\n' "$NOW_TS"
    printf '%s\n' '{"producer":"/debug","scope":"x","summary":"old accessed","tags":["bug"],"type":"discovery","ts":"2020-01-01T00:00:00Z","trust":"inferred","access_count":5,"recurrence_count":1,"dedup_key":"acc1"}'
    printf '%s\n' '{"producer":"/debug","scope":"x","summary":"already dep","tags":["bug"],"type":"diagnosis","ts":"2020-01-01T00:00:00Z","trust":"inferred","access_count":0,"recurrence_count":1,"deprecated":true,"dedup_key":"dep1"}'
  } > "$LOG"
}

# ===== No log file -> rc=1 =====
new_sandbox
set +e
archive_stale_learnings >/dev/null 2>&1
rc=$?
set -e
[ "$rc" -eq 1 ] \
  && pass "no learnings.jsonl -> rc=1 (nothing to archive)" \
  || fail "no log should rc=1; got $rc"

# ===== Real run flips only the genuinely-stale entry =====
new_sandbox
write_corpus
n_before=$(line_count)
set +e
archive_stale_learnings >/dev/null 2>&1
rc=$?
set -e
[ "$rc" -eq 0 ] \
  && pass "real run with a stale candidate -> rc=0" \
  || fail "real run should rc=0; got $rc"
[ "$(dep_of stale1)" = "true" ]  && pass "stale entry flipped deprecated:true"        || fail "stale1 not flipped (got '$(dep_of stale1)')"
[ "$(dep_of fresh1)" = "false" ] && pass "fresh entry NOT flipped (fails age>180)"     || fail "fresh1 wrongly flipped"
[ "$(dep_of acc1)" = "false" ]   && pass "accessed entry NOT flipped (access_count!=0)" || fail "acc1 wrongly flipped"
[ "$(dep_of dep1)" = "true" ]    && pass "already-deprecated entry stays deprecated"    || fail "dep1 lost its deprecated flag"
[ "$(line_count)" -eq "$n_before" ] \
  && pass "never deletes: line count preserved ($n_before)" \
  || fail "line count changed $n_before -> $(line_count) (must never delete)"

# ===== Idempotent: a second run finds nothing new -> rc=1 =====
set +e
archive_stale_learnings >/dev/null 2>&1
rc=$?
set -e
[ "$rc" -eq 1 ] \
  && pass "re-run is idempotent (already-deprecated stale entry skipped -> rc=1)" \
  || fail "re-run should rc=1 after everything stale is flipped; got $rc"

# ===== --dry-run reports but does not write =====
new_sandbox
write_corpus
set +e
archive_stale_learnings --dry-run >/dev/null 2>&1
rc=$?
set -e
[ "$rc" -eq 0 ] \
  && pass "--dry-run with a candidate -> rc=0" \
  || fail "--dry-run should rc=0; got $rc"
[ "$(dep_of stale1)" = "false" ] \
  && pass "--dry-run did NOT write (stale1 still un-flipped)" \
  || fail "--dry-run mutated the log (stale1='$(dep_of stale1)')"

# ===== Malformed line -> refuse rewrite, file intact (audit trail) =====
new_sandbox
write_corpus
printf '%s\n' 'this-is-not-json{{{' >> "$LOG"
cp "$LOG" "$LOG.snap"
set +e
archive_stale_learnings >/dev/null 2>&1
rc=$?
set -e
[ "$rc" -eq 2 ] \
  && pass "malformed line -> rc=2 (refuse rewrite)" \
  || fail "malformed line should rc=2; got $rc"
cmp -s "$LOG" "$LOG.snap" \
  && pass "malformed line: log left byte-for-byte intact (no audit-trail loss)" \
  || fail "log was rewritten despite a malformed line"

# ===== Non-numeric GENIRO_DECAY_TAU_DAYS -> rc=2 =====
new_sandbox
write_corpus
set +e
GENIRO_DECAY_TAU_DAYS="ninety" archive_stale_learnings >/dev/null 2>&1
rc=$?
set -e
[ "$rc" -eq 2 ] \
  && pass "non-numeric GENIRO_DECAY_TAU_DAYS -> rc=2" \
  || fail "bad tau should rc=2; got $rc"

# ===== Verification-coverage line: identical dry-run vs real-run number =====
# The corpus has 4 entries; dep1 is already deprecated. Coverage is tallied over
# the PRE-FLIP on-disk log in BOTH modes, so the number is identical dry-vs-real:
# the live set is {stale1(inferred), fresh1(verified), acc1(inferred)} = 3 live,
# 1 verified -> 33%. (Tallying over the post-flip $processed stream would have
# shrunk the real-run denominator to 2 live -> 50%; that drift is the L1 bug.)
new_sandbox
write_corpus
set +e
cov_out=$(archive_stale_learnings 2>&1 >/dev/null)
rc=$?
set -e
[ "$rc" -eq 0 ] \
  && pass "coverage real run -> rc=0" \
  || fail "coverage real run should rc=0; got $rc"
if printf '%s' "$cov_out" | grep -q 'coverage: verified 1/3 (33%)'; then
  pass "coverage line: verified 1/3 (33%) over the pre-flip live set (real run)"
else
  fail "coverage line wrong/missing: $(printf '%s' "$cov_out" | grep -i coverage || echo '(none)')"
fi

# ===== Coverage prints even when 0 entries are stale (rc=1 early-return path) =====
# A re-run finds nothing new stale (everything stale is already deprecated) but
# the coverage line must still surface — it rides BEFORE the stale_count==0
# early-return. The on-disk log now has stale1 flipped, so the live set is
# {fresh1(verified), acc1(inferred)} = 2 live, 1 verified -> 50%.
set +e
cov_out=$(archive_stale_learnings 2>&1 >/dev/null)
rc=$?
set -e
[ "$rc" -eq 1 ] \
  && pass "coverage when nothing stale -> rc=1 (idempotent re-run)" \
  || fail "re-run should rc=1; got $rc"
if printf '%s' "$cov_out" | grep -q 'coverage: verified 1/2 (50%)'; then
  pass "coverage line prints on the 0-stale early-return path"
else
  fail "coverage line missing on the 0-stale path: $(printf '%s' "$cov_out" | grep -i coverage || echo '(none)')"
fi

# ===== Empty (all-deprecated) live set -> coverage: n/a (no 0/0) =====
new_sandbox
{
  printf '%s\n' '{"producer":"/debug","scope":"x","summary":"dep a","tags":["bug"],"type":"diagnosis","ts":"2020-01-01T00:00:00Z","trust":"verified","access_count":5,"recurrence_count":1,"deprecated":true,"dedup_key":"depa"}'
  printf '%s\n' '{"producer":"/debug","scope":"x","summary":"dep b","tags":["bug"],"type":"diagnosis","ts":"2020-01-01T00:00:00Z","trust":"inferred","access_count":5,"recurrence_count":1,"deprecated":true,"dedup_key":"depb"}'
} > "$LOG"
set +e
cov_out=$(archive_stale_learnings 2>&1 >/dev/null)
set -e
if printf '%s' "$cov_out" | grep -q 'coverage: n/a'; then
  pass "empty live set -> coverage: n/a (never 0/0)"
else
  fail "empty live set should report n/a: $(printf '%s' "$cov_out" | grep -i coverage || echo '(none)')"
fi

# ===== Coverage on the --dry-run report — SAME number as the real run =====
new_sandbox
write_corpus
set +e
cov_out=$(archive_stale_learnings --dry-run 2>&1 >/dev/null)
set -e
# Dry-run tallies the PRE-flip live set: 3 live, 1 verified -> 33%. Identical to
# the real-run number above (both compute off the on-disk log) — that dry==real
# consistency is the L1 fix; dry-run previously reported 50% on this same corpus.
if printf '%s' "$cov_out" | grep -q 'coverage: verified 1/3 (33%)'; then
  pass "coverage line present on --dry-run report (same 1/3 as real run)"
else
  fail "coverage line missing on --dry-run: $(printf '%s' "$cov_out" | grep -i coverage || echo '(none)')"
fi

# ===== Direct invocation takes the rewrite lock =====
new_sandbox
write_corpus
mkdir "$(dirname "$LOG")/.archive-stale.lock"
set +e
out=$(bash "$REPO_ROOT/lib/archive-stale.sh" 2>&1); rc=$?
set -e
if [ "$rc" -eq 3 ] && printf '%s' "$out" | grep -q 'lock held'; then
  pass "direct invocation skips with rc=3 while the lock is held"
else
  fail "direct-run lock skip; rc=$rc (expect 3) out=$out"
fi
rmdir "$(dirname "$LOG")/.archive-stale.lock"

set +e
bash "$REPO_ROOT/lib/archive-stale.sh" >/dev/null 2>&1; rc=$?
set -e
if { [ "$rc" -eq 0 ] || [ "$rc" -eq 1 ]; } && [ ! -d "$(dirname "$LOG")/.archive-stale.lock" ]; then
  pass "direct invocation acquires and releases the lock (rc=$rc)"
else
  fail "direct-run lock release; rc=$rc lock-left=$([ -d "$(dirname "$LOG")/.archive-stale.lock" ] && echo y || echo n)"
fi

echo
echo "Tests run:    $TESTS_RUN"
echo "Tests failed: $TESTS_FAILED"
[ "$TESTS_FAILED" -eq 0 ]
