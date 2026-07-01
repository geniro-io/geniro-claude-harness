#!/usr/bin/env bash
# Smoke test for lib/resolve-conflicts.sh

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
# shellcheck disable=SC1091
source "$REPO_ROOT/lib/resolve-conflicts.sh"

TESTS_RUN=0
TESTS_FAILED=0
pass() { TESTS_RUN=$((TESTS_RUN + 1)); echo "PASS: $1"; }
fail() { TESTS_RUN=$((TESTS_RUN + 1)); TESTS_FAILED=$((TESTS_FAILED + 1)); echo "FAIL: $1" >&2; }

# Soft notice with all three layers
out=$(emit_conflict_notice \
  --subject "http library" \
  --l4 "use axios" --l4-source ".geniro/instructions/global.md" \
  --l3 "no axios in package.json" --l3-source ".geniro/planning/_project.md" \
  --l2 "migrated to fetch" --l2-source "dedup_key=a1b2c3" \
  --following L4 \
  --suggested-action "Consider /geniro:instructions edit global.md.")

case "$out" in
  *'[layer-conflict] subject: http library'*) pass "soft notice has subject header" ;;
  *) fail "soft notice missing subject header — got: $out" ;;
esac

case "$out" in
  *'L4 rule (project rules) .geniro/instructions/global.md: use axios'*) pass "soft notice has L4 line with source" ;;
  *) fail "L4 line malformed" ;;
esac
case "$out" in
  *'L3 fact (project snapshot) .geniro/planning/_project.md: no axios in package.json'*) pass "soft notice has L3 line with source" ;;
  *) fail "L3 line malformed" ;;
esac
case "$out" in
  *'L2 history (past learnings) dedup_key=a1b2c3: migrated to fetch'*) pass "soft notice has L2 line with source" ;;
  *) fail "L2 line malformed" ;;
esac

case "$out" in
  *'→ Skill is following L4 (precedence). Consider /geniro:instructions edit global.md.'*)
    pass "soft notice footer with following + suggested-action"
    ;;
  *) fail "soft notice footer malformed — got: $out" ;;
esac

# Soft notice — only L4 (no L3 / L2)
out=$(emit_conflict_notice \
  --subject "build tool" \
  --l4 "use webpack" \
  --following L4)
case "$out" in
  *'L4 rule (project rules): use webpack'*) pass "soft notice with L4 only (no source) renders L4 rule prefix" ;;
  *) fail "L4-only notice format wrong" ;;
esac
case "$out" in
  *'L3'*|*'L2'*) fail "L3/L2 lines should not appear when not supplied" ;;
  *) pass "soft notice omits absent layers" ;;
esac

# Soft notice — no following
out=$(emit_conflict_notice --subject "x" --l4 "rule")
case "$out" in
  *'Skill is following'*) fail "should NOT have 'Skill is following' when --following absent" ;;
  *) pass "no --following → no footer line" ;;
esac

# Hard conflict block
out=$(hard_conflict_block \
  --subject "http library" \
  --l4 "use axios" --l4-source ".geniro/instructions/global.md" \
  --l3 "axios removed; fetch in use" --l3-source ".geniro/planning/_project.md" \
  --suggested-action "After you decide, /geniro:instructions edit global.md to refresh L4.")
case "$out" in
  *'Hard cross-layer conflict on: http library'*) pass "hard block header" ;;
  *) fail "hard block header missing — got: $out" ;;
esac
case "$out" in
  *'L4 rule (project rules) (.geniro/instructions/global.md): use axios'*) pass "hard block has L4 rule with source" ;;
  *) fail "L4 rule line wrong" ;;
esac
case "$out" in
  *'L3 fact (project snapshot) (.geniro/planning/_project.md): axios removed; fetch in use'*) pass "hard block has L3 fact with source" ;;
  *) fail "L3 fact line wrong" ;;
esac
case "$out" in
  *'After you decide, /geniro:instructions edit global.md to refresh L4.'*) pass "hard block has suggested-action footer" ;;
  *) fail "hard block missing suggested-action" ;;
esac

# Flag validation
set +e
emit_conflict_notice --l4 "x" 2>/dev/null
rc=$?
set -e
if [ "$rc" -eq 64 ]; then
  pass "missing --subject → rc=64"
else
  fail "missing --subject should rc=64; got $rc"
fi

set +e
emit_conflict_notice --subject "x" --following BAD 2>/dev/null
rc=$?
set -e
if [ "$rc" -eq 64 ]; then
  pass "bad --following → rc=64"
else
  fail "bad --following should rc=64; got $rc"
fi

set +e
emit_conflict_notice --subject "x" --bogus y 2>/dev/null
rc=$?
set -e
if [ "$rc" -eq 64 ]; then
  pass "unknown flag → rc=64"
else
  fail "unknown flag should rc=64; got $rc"
fi

# Trailing value-taking flag (missing operand) → rc=64, not a parse-loop spin
# (`shift 2` with $#=1 no-ops, so an unguarded arm loops on the flag forever).
set +e
emit_conflict_notice --subject "x" --l4 2>/dev/null
rc=$?
set -e
if [ "$rc" -eq 64 ]; then
  pass "trailing --l4 (missing operand) → rc=64"
else
  fail "trailing --l4 should rc=64; got $rc"
fi

# Empty content (just subject) — should still emit header line
out=$(emit_conflict_notice --subject "stub")
case "$out" in
  *'[layer-conflict] subject: stub'*) pass "subject-only call emits header at minimum" ;;
  *) fail "subject-only output: '$out'" ;;
esac

echo
echo "Tests run:    $TESTS_RUN"
echo "Tests failed: $TESTS_FAILED"
[ "$TESTS_FAILED" -eq 0 ]
