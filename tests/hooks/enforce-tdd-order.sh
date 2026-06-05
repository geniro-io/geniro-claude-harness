#!/usr/bin/env bash
# Smoke test for hooks/enforce-tdd-order.sh (PreToolUse Edit|Write|MultiEdit, hard-block in RED).
#
# Run: bash tests/hooks/enforce-tdd-order.sh
#
# Coverage:
#   - No TDD state file → not opted in → allow.
#   - RED phase blocks production-code edits (Edit AND MultiEdit), allows test files.
#   - Test-substring-but-not-a-test (contestant.ts) is treated as production → blocked.
#   - GREEN / IDLE phase → allow production.
#   - safety.json tdd-order bypass.
#   - Missing file_path fails-open.
#
# Uses an isolated git repo so the branch slug (and thus the state-file path) is deterministic.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
HOOK="$REPO_ROOT/hooks/enforce-tdd-order.sh"

TMPDIR_BASE="$(mktemp -d)"
ORIGINAL_PWD="$PWD"
trap 'cd "$ORIGINAL_PWD"; rm -rf "$TMPDIR_BASE"' EXIT

TESTS_RUN=0
TESTS_FAILED=0
pass() { TESTS_RUN=$((TESTS_RUN + 1)); echo "PASS: $1"; }
fail() { TESTS_RUN=$((TESTS_RUN + 1)); TESTS_FAILED=$((TESTS_FAILED + 1)); echo "FAIL: $1" >&2; }
expect_block() { if [ "$2" = "2" ]; then pass "$1"; else fail "$1 (expected exit=2, got exit=$2)"; fi; }
expect_allow() { if [ "$2" = "0" ]; then pass "$1"; else fail "$1 (expected exit=0, got exit=$2)"; fi; }

run_edit() {
  jq -nc --arg p "$1" '{tool_input: {file_path: $p, new_string: "x"}}' | bash "$HOOK" >/dev/null 2>&1
  echo $?
}
run_multiedit() {
  jq -nc --arg p "$1" '{tool_input: {file_path: $p, edits: [{old_string: "a", new_string: "b"}]}}' | bash "$HOOK" >/dev/null 2>&1
  echo $?
}

# Isolated git repo so `git branch --show-current` (the slug source) is deterministic.
GITREPO="$TMPDIR_BASE/repo"
mkdir -p "$GITREPO"
cd "$GITREPO" || exit 1
git init -q
git checkout -q -b tddbranch
SLUG="tddbranch"
STATE_FILE=".geniro/state/tdd/state-${SLUG}.md"
mkdir -p "$(dirname "$STATE_FILE")"
write_phase() { printf '## phase\n%s\n' "$1" > "$STATE_FILE"; }

# ===== No state file → not opted in → allow =====
rm -f "$STATE_FILE"
expect_allow "no TDD state file → production edit allowed" "$(run_edit "$GITREPO/src/app.js")"

# ===== RED phase =====
write_phase RED
expect_block "RED: production file blocked"            "$(run_edit "$GITREPO/src/app.js")"
expect_block "RED: production file blocked (MultiEdit)" "$(run_multiedit "$GITREPO/src/app.js")"
expect_allow "RED: *.test.js allowed"                  "$(run_edit "$GITREPO/src/app.test.js")"
expect_allow "RED: tests/ dir allowed"                 "$(run_edit "$GITREPO/tests/app.js")"
expect_block "RED: 'contestant.ts' (test-substring, not a test) blocked" "$(run_edit "$GITREPO/src/contestant.ts")"

# ===== GREEN / IDLE → allow production =====
write_phase GREEN
expect_allow "GREEN: production file allowed"          "$(run_edit "$GITREPO/src/app.js")"
write_phase IDLE
expect_allow "IDLE: production file allowed"           "$(run_edit "$GITREPO/src/app.js")"

# ===== safety.json tdd-order bypass =====
write_phase RED
mkdir -p "$GITREPO/.geniro"
echo '{"allow_patterns": ["tdd-order"]}' > "$GITREPO/.geniro/safety.json"
expect_allow "RED + tdd-order bypass: production allowed" "$(run_edit "$GITREPO/src/app.js")"
rm -f "$GITREPO/.geniro/safety.json"

# ===== Missing file_path → allow =====
expect_allow "missing file_path → allow" "$(echo '{"tool_input": {}}' | bash "$HOOK" >/dev/null 2>&1; echo $?)"

echo
echo "Tests run: $TESTS_RUN, failed: $TESTS_FAILED"
[ "$TESTS_FAILED" -eq 0 ]
