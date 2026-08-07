#!/usr/bin/env bash
# Suite for lib/audit-ledger.sh — fingerprint stability and ledger semantics.
#
# Run: bash tests/audit/ledger.sh
# Exits non-zero on any failure.
#
# The fingerprint's whole value is WHICH edits move it and which do not, so each
# property gets a paired case: an edit that must NOT move the key, and an edit
# that must. A fingerprint that never moves suppresses a real regression; one
# that always moves is a line number with extra steps.
#
# Plugin-developer tooling only — not shipped to user projects.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"

TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT

export GENIRO_AUDIT_LEDGER="$TMPDIR/ledger.tsv"
# shellcheck disable=SC1091
source "$REPO_ROOT/lib/audit-ledger.sh"

TESTS_RUN=0
TESTS_FAILED=0
pass() { TESTS_RUN=$((TESTS_RUN + 1)); echo "PASS: $1"; }
fail() { TESTS_RUN=$((TESTS_RUN + 1)); TESTS_FAILED=$((TESTS_FAILED + 1)); echo "FAIL: $1" >&2; }

FIX="$TMPDIR/fixture.md"
_write_fixture() {
  cat > "$FIX" <<'EOF'
# heading one

Some opening prose that sits above the finding and can grow.

## the section that carries the finding

The cited sentence lives here and is what the fingerprint hashes, together
with the hundred characters of context that follow it across line boundaries.

## a later section

Trailing content.
EOF
}
_write_fixture
BASE_FP="$(ledger_fingerprint "$FIX" 7)"

# --- fingerprint: what must NOT move it --------------------------------------

_write_fixture
awk 'NR==1{ for(i=0;i<25;i++) print "inserted line above" } { print }' "$FIX" > "$FIX.new" && mv "$FIX.new" "$FIX"
if [ "$(ledger_fingerprint "$FIX" 32)" = "$BASE_FP" ]; then
  pass "25 lines inserted above the finding do not move the fingerprint"
else
  fail "line insertion above the finding moved the fingerprint"
fi

_write_fixture
awk 'NR==7 { $0 = "      " $0 "    " } { print }' "$FIX" > "$FIX.new" && mv "$FIX.new" "$FIX"
if [ "$(ledger_fingerprint "$FIX" 7)" = "$BASE_FP" ]; then
  pass "re-indenting the cited line does not move the fingerprint"
else
  fail "re-indentation moved the fingerprint"
fi

_write_fixture
printf '\r\n' >/dev/null; sed 's/$/\r/' "$FIX" > "$FIX.new" && mv "$FIX.new" "$FIX"
if [ "$(ledger_fingerprint "$FIX" 7)" = "$BASE_FP" ]; then
  pass "a CRLF checkout produces the same fingerprint as an LF one"
else
  fail "CRLF line endings moved the fingerprint"
fi

# --- fingerprint: what MUST move it ------------------------------------------

_write_fixture
awk 'NR==7 { $0 = "An entirely different sentence replaces the cited one." } { print }' "$FIX" > "$FIX.new" && mv "$FIX.new" "$FIX"
if [ "$(ledger_fingerprint "$FIX" 7)" != "$BASE_FP" ]; then
  pass "rewriting the cited line moves the fingerprint (the finding reopens)"
else
  fail "rewriting the cited line left the fingerprint unchanged"
fi

_write_fixture
awk 'NR==8 { $0 = "Context after the finding, rewritten entirely, changes the window." } { print }' "$FIX" > "$FIX.new" && mv "$FIX.new" "$FIX"
if [ "$(ledger_fingerprint "$FIX" 7)" != "$BASE_FP" ]; then
  pass "rewriting the following context moves the fingerprint (100-char window spans lines)"
else
  fail "the context window does not reach past the cited line"
fi

# --- ledger semantics ---------------------------------------------------------

_write_fixture
rm -f "$GENIRO_AUDIT_LEDGER"
ledger_record "$FIX" 7 dedup T4 rejected r5 "copies have not diverged" >/dev/null
ledger_record "$FIX" 7 dedup T4 rejected r6 "copies have not diverged" >/dev/null
ledger_record "$FIX" 7 dedup T4 rejected r7 "copies have not diverged" >/dev/null

rows="$(grep -vc '^#' "$GENIRO_AUDIT_LEDGER")"
if [ "$rows" = 1 ]; then
  pass "the same finding across three runs collapses to one row"
else
  fail "three runs of one finding produced $rows rows, want 1"
fi

if [ "$(ledger_run_count "$FIX" "$BASE_FP" dedup)" = 3 ]; then
  pass "run count reaches 3 — the convergence signal for a no-oracle finding"
else
  fail "run count is $(ledger_run_count "$FIX" "$BASE_FP" dedup), want 3"
fi

if [ "$(ledger_lookup "$FIX" "$BASE_FP" dedup)" = rejected ]; then
  pass "a recorded rejection is readable back by (fingerprint, file, class)"
else
  fail "lookup did not return the recorded disposition"
fi

if [ -z "$(ledger_lookup "$FIX" "$BASE_FP" stale-ref)" ]; then
  pass "a different class at the same location does not inherit the rejection"
else
  fail "class is not part of the key — a rejection leaked across classes"
fi

# The key is the last TWO path segments, so a file keeps its row when the path
# ABOVE its own directory changes — a worktree, a clone at a different prefix,
# a component moved wholesale — but not when it changes component.
holder="$(basename "$TMPDIR")"
mkdir -p "$TMPDIR/deeper/$holder"
cp "$FIX" "$TMPDIR/deeper/$holder/fixture.md"
if [ "$(ledger_lookup "$TMPDIR/deeper/$holder/fixture.md" "$BASE_FP" dedup)" = rejected ]; then
  pass "a deeper path prefix keeps the ledger row (key is the last two segments)"
else
  fail "a changed path prefix orphaned the ledger row"
fi

# The reason the key is not the bare basename: 20 files in this repo are named
# SKILL.md, and a bare-basename key would let a rejection recorded for one skill
# suppress the same class in every other skill.
mkdir -p "$TMPDIR/other"
cp "$FIX" "$TMPDIR/other/fixture.md"
if [ -z "$(ledger_lookup "$TMPDIR/other/fixture.md" "$BASE_FP" dedup)" ]; then
  pass "a same-named file in a different component does NOT inherit the rejection"
else
  fail "the key collapsed two different files — a rejection leaked across components"
fi

# --- guards -------------------------------------------------------------------

if ! ledger_record "$FIX" 7 orphan T4 rejected r8 >/dev/null 2>&1; then
  pass "a rejection with no reason is refused"
else
  fail "a reasonless rejection was accepted"
fi

if ! ledger_record "$FIX" 7 orphan T4 wontfix r8 "why" >/dev/null 2>&1; then
  pass "an unknown disposition is refused"
else
  fail "an unknown disposition was accepted"
fi

if ! ledger_record "$FIX" 7 "Not A Slug" T4 fixed r8 >/dev/null 2>&1; then
  pass "a non-slug class is refused"
else
  fail "a non-slug class was accepted"
fi

if ledger_validate >/dev/null 2>&1; then
  pass "a well-formed ledger validates"
else
  fail "a well-formed ledger failed validation"
fi

printf 'garbage\trow\n' >> "$GENIRO_AUDIT_LEDGER"
if ! ledger_validate >/dev/null 2>&1; then
  pass "a malformed row fails validation"
else
  fail "a malformed row passed validation"
fi

# --- prune --------------------------------------------------------------------

rm -f "$GENIRO_AUDIT_LEDGER"
ledger_record "$FIX" 7 dedup T4 rejected r7 "kept — file still exists" >/dev/null
GENIRO_REPO_ROOT="$TMPDIR" ledger_prune >/dev/null 2>&1
if grep -q 'fixture.md' "$GENIRO_AUDIT_LEDGER"; then
  pass "prune keeps a row whose file is still present"
else
  fail "prune dropped a row whose file exists"
fi

printf '0000deadbeef\tvanished-file.md\tstale-ref\tT3\trejected\tr3\tgone\n' >> "$GENIRO_AUDIT_LEDGER"
GENIRO_REPO_ROOT="$TMPDIR" ledger_prune >/dev/null 2>&1
if ! grep -q 'vanished-file.md' "$GENIRO_AUDIT_LEDGER"; then
  pass "prune drops a row whose file is gone (ESLint --prune-suppressions shape)"
else
  fail "prune kept a row for a file that no longer exists"
fi

echo
echo "Ran $TESTS_RUN tests, $TESTS_FAILED failed."
[ "$TESTS_FAILED" -eq 0 ] || exit 1
