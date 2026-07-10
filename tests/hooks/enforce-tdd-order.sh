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
# Bash-form payload: the command writes a file via heredoc / redirect / tee. The
# Bash branch extracts the write target and applies the same test-vs-production
# classification as the Edit path.
run_bash() {
  jq -nc --arg c "$1" '{tool_name: "Bash", tool_input: {command: $c}}' | bash "$HOOK" >/dev/null 2>&1
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

# ===== RED enforced from a subdirectory cwd (state path is root-resolved) =====
write_phase RED
mkdir -p "$GITREPO/src/deep"
cd "$GITREPO/src/deep" || exit 1
expect_block "RED from subdir cwd: production file blocked" "$(run_edit "$GITREPO/src/app.js")"
cd "$GITREPO" || exit 1

# ===== safety.json tdd-order bypass =====
write_phase RED
mkdir -p "$GITREPO/.geniro"
echo '{"allow_patterns": ["tdd-order"]}' > "$GITREPO/.geniro/safety.json"
expect_allow "RED + tdd-order bypass: production allowed" "$(run_edit "$GITREPO/src/app.js")"
rm -f "$GITREPO/.geniro/safety.json"

# ===== Missing file_path → allow =====
expect_allow "missing file_path → allow" "$(echo '{"tool_input": {}}' | bash "$HOOK" >/dev/null 2>&1; echo $?)"

# ===== Bash branch: shell-side writes are gated like Edits during RED =====
write_phase RED
expect_block "RED: Bash heredoc into production src/app.js blocked" \
  "$(run_bash "$(printf 'cat > %s/src/app.js <<EOF\nconst x = 1;\nEOF\n' "$GITREPO")")"
expect_allow "RED: Bash heredoc into test file src/app.test.js allowed" \
  "$(run_bash "$(printf 'cat > %s/src/app.test.js <<EOF\ntest()\nEOF\n' "$GITREPO")")"
expect_block "RED: Bash redirect into production app.py blocked" \
  "$(run_bash "printf abc > $GITREPO/app.py")"
expect_allow "RED: Bash redirect into tests/ dir allowed" \
  "$(run_bash "printf abc > $GITREPO/tests/helper.js")"
# A bash command whose only write target is a pseudo-device (2>/dev/null) is not
# production source — allowed, so ordinary RED-phase commands aren't surprised.
expect_allow "RED: Bash 2>/dev/null only (no production write) allowed" \
  "$(run_bash 'pytest 2>/dev/null')"
# The TDD orchestrator's own RED-phase state write lands under .geniro/ — skipped,
# else the mktemp+mv that advances the cycle would deadlock.
expect_allow "RED: Bash write under .geniro/ allowed (orchestrator state)" \
  "$(run_bash "mv /tmp/x $GITREPO/.geniro/state/tdd/state-${SLUG}.md")"
expect_allow "RED: Bash read-only command (no write target) allowed" \
  "$(run_bash "cat $GITREPO/src/app.js | grep foo")"
# Outside RED, Bash writes to production are allowed.
write_phase GREEN
expect_allow "GREEN: Bash heredoc into production allowed" \
  "$(run_bash "$(printf 'cat > %s/src/app.js <<EOF\nx\nEOF\n' "$GITREPO")")"
# ===== RED: additional Bash write vectors are gated like Edits =====
write_phase RED
expect_block "RED: truncate on production src blocked" \
  "$(run_bash "truncate -s 0 $GITREPO/src/app.js")"
expect_block "RED: shred on production src blocked" \
  "$(run_bash "shred -u $GITREPO/src/app.py")"
expect_block "RED: install into production src blocked" \
  "$(run_bash "install -m 644 /tmp/x $GITREPO/src/app.ts")"
expect_block "RED: ln -sf over production src blocked" \
  "$(run_bash "ln -sf /tmp/x $GITREPO/src/app.rb")"
expect_allow "RED: truncate on a test file allowed" \
  "$(run_bash "truncate -s 0 $GITREPO/src/app.test.js")"
expect_allow "RED: shred on a scratch (non-production, /dev) allowed" \
  "$(run_bash 'dd if=/dev/zero of=/dev/null')"
# Spaced-tag heredoc must be recognized so its target is classified — a spaced
# `<< EOF` into production blocks; into a test file allows.
expect_block "RED: spaced-tag heredoc into production blocked" \
  "$(run_bash "$(printf 'cat > %s/src/app.js << EOF\nconst x = 1;\nEOF\n' "$GITREPO")")"
expect_allow "RED: spaced-tag heredoc into a test file allowed" \
  "$(run_bash "$(printf 'cat > %s/src/app.test.js << EOF\ntest()\nEOF\n' "$GITREPO")")"

# No TDD state file → not opted in → Bash production write allowed.
write_phase RED
rm -f "$STATE_FILE"
expect_allow "no state file: Bash production write allowed" \
  "$(run_bash "$(printf 'cat > %s/src/app.js <<EOF\nx\nEOF\n' "$GITREPO")")"

echo
echo "Tests run: $TESTS_RUN, failed: $TESTS_FAILED"
[ "$TESTS_FAILED" -eq 0 ]
