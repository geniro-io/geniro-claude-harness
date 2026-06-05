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

echo
echo "Tests run:    $TESTS_RUN"
echo "Tests failed: $TESTS_FAILED"
[ "$TESTS_FAILED" -eq 0 ]
