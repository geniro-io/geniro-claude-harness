#!/usr/bin/env bash
# Smoke test for hooks/block-config-weakening.sh (PreToolUse Edit|Write|MultiEdit).
#
# Run: bash tests/hooks/block-config-weakening.sh
#
# Coverage:
#   - Editing an EXISTING lint/formatter/type-checker config blocks (exit 2).
#   - First-time creation (path not on disk) allows.
#   - Backup/disabled copies (.bak/.old/...) allow.
#   - Non-config files allow.
#   - safety.json config-weakening bypass.
#   - MultiEdit form is guarded (file_path-based).
#   - Missing file_path fails-open.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
HOOK="$REPO_ROOT/hooks/block-config-weakening.sh"

TMPDIR_BASE="$(mktemp -d)"
ORIGINAL_PWD="$PWD"
trap 'cd "$ORIGINAL_PWD"; rm -rf "$TMPDIR_BASE"' EXIT

TESTS_RUN=0
TESTS_FAILED=0
pass() { TESTS_RUN=$((TESTS_RUN + 1)); echo "PASS: $1"; }
fail() { TESTS_RUN=$((TESTS_RUN + 1)); TESTS_FAILED=$((TESTS_FAILED + 1)); echo "FAIL: $1" >&2; }

run_edit() {
  jq -nc --arg p "$1" '{tool_input: {file_path: $p, new_string: "{}"}}' | bash "$HOOK" >/dev/null 2>&1
  echo $?
}
run_multiedit() {
  jq -nc --arg p "$1" '{tool_input: {file_path: $p, edits: [{old_string: "a", new_string: "b"}]}}' | bash "$HOOK" >/dev/null 2>&1
  echo $?
}
expect_block() { if [ "$2" = "2" ]; then pass "$1"; else fail "$1 (expected exit=2, got exit=$2)"; fi; }
expect_allow() { if [ "$2" = "0" ]; then pass "$1"; else fail "$1 (expected exit=0, got exit=$2)"; fi; }

# Existing config files on disk.
: > "$TMPDIR_BASE/tsconfig.json"
: > "$TMPDIR_BASE/.eslintrc.json"
: > "$TMPDIR_BASE/biome.json"
: > "$TMPDIR_BASE/ruff.toml"
: > "$TMPDIR_BASE/.golangci.yml"
: > "$TMPDIR_BASE/.eslintrc.bak"
: > "$TMPDIR_BASE/app.js"
cd "$TMPDIR_BASE" || exit 1

# ===== Editing an existing config blocks =====
expect_block "edit existing tsconfig.json blocked"   "$(run_edit "$TMPDIR_BASE/tsconfig.json")"
expect_block "edit existing .eslintrc.json blocked"  "$(run_edit "$TMPDIR_BASE/.eslintrc.json")"
expect_block "edit existing biome.json blocked"      "$(run_edit "$TMPDIR_BASE/biome.json")"
expect_block "edit existing ruff.toml blocked"       "$(run_edit "$TMPDIR_BASE/ruff.toml")"
expect_block "edit existing .golangci.yml blocked"   "$(run_edit "$TMPDIR_BASE/.golangci.yml")"
expect_block "MultiEdit existing tsconfig.json blocked" "$(run_multiedit "$TMPDIR_BASE/tsconfig.json")"

# ===== First-time creation + backups + non-config allow =====
expect_allow "create NEW tsconfig.json (not on disk) allows" "$(run_edit "$TMPDIR_BASE/sub/tsconfig.json")"
expect_allow "edit .eslintrc.bak backup allows"      "$(run_edit "$TMPDIR_BASE/.eslintrc.bak")"
expect_allow "edit non-config app.js allows"         "$(run_edit "$TMPDIR_BASE/app.js")"

# ===== safety.json bypass =====
mkdir -p "$TMPDIR_BASE/proj/.geniro"
echo '{"allow_patterns": ["config-weakening"]}' > "$TMPDIR_BASE/proj/.geniro/safety.json"
: > "$TMPDIR_BASE/proj/tsconfig.json"
cd "$TMPDIR_BASE/proj" || exit 1
expect_allow "safety.json bypass allows existing config edit" "$(run_edit "$TMPDIR_BASE/proj/tsconfig.json")"
cd "$TMPDIR_BASE" || exit 1

# ===== Fail-open on missing file_path =====
expect_allow "missing file_path → allow" "$(echo '{"tool_input": {}}' | bash "$HOOK" >/dev/null 2>&1; echo $?)"

echo
echo "Tests run: $TESTS_RUN, failed: $TESTS_FAILED"
[ "$TESTS_FAILED" -eq 0 ]
