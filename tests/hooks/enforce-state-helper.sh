#!/usr/bin/env bash
# Smoke test for hooks/enforce-state-helper.sh (PreToolUse Edit|Write|MultiEdit, warn-mode).
#
# Run: bash tests/hooks/enforce-state-helper.sh
#
# Coverage:
#   - State-path write warns (stderr + user-visible systemMessage) but allows (exit 0).
#   - JSONL knowledge path suggests atomic_state_append; others atomic_state_write.
#   - Excluded transient files (locks, notes.md, .tmp) stay silent.
#   - Non-state paths stay silent.
#   - enforce-state-helper bypass via safety.json.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
HOOK="$REPO_ROOT/hooks/enforce-state-helper.sh"

TMPDIR_BASE="$(mktemp -d)"
ORIGINAL_PWD="$PWD"
trap 'cd "$ORIGINAL_PWD"; rm -rf "$TMPDIR_BASE"' EXIT

TESTS_RUN=0
TESTS_FAILED=0
pass() { TESTS_RUN=$((TESTS_RUN + 1)); echo "PASS: $1"; }
fail() { TESTS_RUN=$((TESTS_RUN + 1)); TESTS_FAILED=$((TESTS_FAILED + 1)); echo "FAIL: $1" >&2; }

run_path() {
  jq -nc --arg p "$1" '{tool_input: {file_path: $p, content: "x"}}' | bash "$HOOK" 2>&1
}
rc_path() {
  jq -nc --arg p "$1" '{tool_input: {file_path: $p, content: "x"}}' | bash "$HOOK" >/dev/null 2>&1
  echo $?
}

cd "$TMPDIR_BASE" || exit 1

out=$(run_path '/proj/.geniro/state/handoff/from-review-main.md')
if [ "$(rc_path '/proj/.geniro/state/handoff/from-review-main.md')" = "0" ]; then
  pass "warn mode allows the call (exit 0)"
else
  fail "warn mode allows the call (exit 0)"
fi
if printf '%s' "$out" | grep -q 'atomic_state_write'; then
  pass "state path suggests atomic_state_write"
else
  fail "state path suggests atomic_state_write"
fi
if printf '%s' "$out" | grep -q 'systemMessage'; then
  pass "warning carries a user-visible systemMessage"
else
  fail "warning carries a user-visible systemMessage"
fi

out=$(run_path '/proj/.geniro/knowledge/learnings.jsonl')
if printf '%s' "$out" | grep -q 'atomic_state_append'; then
  pass "jsonl knowledge path suggests atomic_state_append"
else
  fail "jsonl knowledge path suggests atomic_state_append"
fi

if [ -z "$(run_path '/proj/src/app.js')" ]; then
  pass "non-state path stays silent"
else
  fail "non-state path stays silent"
fi
if [ -z "$(run_path '/proj/.geniro/planning/.codebase-map.lock')" ]; then
  pass "lock file is excluded"
else
  fail "lock file is excluded"
fi
if [ -z "$(run_path '/proj/.geniro/planning/task-dir/notes.md')" ]; then
  pass "scratch notes.md is excluded"
else
  fail "scratch notes.md is excluded"
fi
if [ -z "$(run_path '/proj/.geniro/state/x/state.md.tmp.123.host')" ]; then
  pass "atomic-write temp file is excluded"
else
  fail "atomic-write temp file is excluded"
fi

# ===== safety.json bypass =====
mkdir -p "$TMPDIR_BASE/byp/.geniro"
echo '{"allow_patterns":["enforce-state-helper"]}' > "$TMPDIR_BASE/byp/.geniro/safety.json"
cd "$TMPDIR_BASE/byp" || exit 1
if [ -z "$(run_path '/proj/.geniro/state/review/slug/state.md')" ]; then
  pass "enforce-state-helper bypass silences the warning"
else
  fail "enforce-state-helper bypass silences the warning"
fi
cd "$TMPDIR_BASE" || exit 1

echo
echo "Tests run: $TESTS_RUN, failed: $TESTS_FAILED"
[ "$TESTS_FAILED" -eq 0 ]
