#!/usr/bin/env bash
# Smoke test for hooks/require-evidence-on-completion.sh (Stop hook, warn-only).
#
# Run: bash tests/hooks/require-evidence-on-completion.sh
#
# The hook always exits 0 (warn-only) — assertions check the WARNING TEXT
# (stderr) and the systemMessage JSON (stdout), not exit codes.
#
# Coverage:
#   - Completion claim without evidence → warning + systemMessage.
#   - Claim with an Evidence Block / file:line citation → silent.
#   - Interrogative ("Do all tests pass?") → silent (question, not claim).
#   - Transcript fallback reads the WHOLE last assistant message, not line 1
#     (head-of-jq-output truncation regression).
#   - Tool-use-only trailing event does not mask the newest text-bearing turn.
#   - evidence-stop bypass via safety.json.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
HOOK="$REPO_ROOT/hooks/require-evidence-on-completion.sh"

TMPDIR_BASE="$(mktemp -d)"
ORIGINAL_PWD="$PWD"
trap 'cd "$ORIGINAL_PWD"; rm -rf "$TMPDIR_BASE"' EXIT

TESTS_RUN=0
TESTS_FAILED=0
pass() { TESTS_RUN=$((TESTS_RUN + 1)); echo "PASS: $1"; }
fail() { TESTS_RUN=$((TESTS_RUN + 1)); TESTS_FAILED=$((TESTS_FAILED + 1)); echo "FAIL: $1" >&2; }

cd "$TMPDIR_BASE" || exit 1

# Feed the message via the last_assistant_message field; capture stdout+stderr.
run_msg() {
  jq -nc --arg m "$1" '{last_assistant_message: $m}' | bash "$HOOK" 2>&1
}

out=$(run_msg 'All tests pass, ready to ship.')
if printf '%s' "$out" | grep -q 'evidence-stop'; then
  pass "completion claim without evidence warns"
else
  fail "completion claim without evidence warns"
fi
if printf '%s' "$out" | grep -q 'systemMessage'; then
  pass "warning carries a user-visible systemMessage"
else
  fail "warning carries a user-visible systemMessage"
fi

out=$(run_msg 'All tests pass.

## Evidence Block
Command: npm test
Exit code: 0
Tail (last 3 lines):
  ok')
if [ -z "$out" ]; then
  pass "claim WITH Evidence Block stays silent"
else
  fail "claim WITH Evidence Block stays silent (got: $out)"
fi

out=$(run_msg 'Refactored the parser; see src/parser.ts:120-145.
All tests pass.')
if [ -z "$out" ]; then
  pass "file:line citation counts as evidence"
else
  fail "file:line citation counts as evidence (got: $out)"
fi

out=$(run_msg 'Do all tests pass?')
if [ -z "$out" ]; then
  pass "interrogative line is not a claim"
else
  fail "interrogative line is not a claim (got: $out)"
fi

# ===== Transcript fallback =====
TR="$TMPDIR_BASE/transcript.jsonl"

# Claim on the SECOND line of the last assistant message — a head -1 of the
# raw jq output used to truncate the message to line 1 and miss this.
{
  jq -nc '{type:"user", message:{content:[{type:"text", text:"hi"}]}}'
  jq -nc '{type:"assistant", message:{content:[{type:"text", text:"Work summary line.\nAll tests pass."}]}}'
} > "$TR"
out=$(jq -nc --arg t "$TR" '{transcript_path: $t}' | bash "$HOOK" 2>&1)
if printf '%s' "$out" | grep -q 'evidence-stop'; then
  pass "transcript fallback scans the whole last message (not line 1 only)"
else
  fail "transcript fallback scans the whole last message"
fi

# A trailing tool-use-only assistant event must not mask the newest
# text-bearing turn.
{
  jq -nc '{type:"assistant", message:{content:[{type:"text", text:"All tests pass."}]}}'
  jq -nc '{type:"assistant", message:{content:[{type:"tool_use", name:"Bash"}]}}'
} > "$TR"
out=$(jq -nc --arg t "$TR" '{transcript_path: $t}' | bash "$HOOK" 2>&1)
if printf '%s' "$out" | grep -q 'evidence-stop'; then
  pass "tool-only trailing event does not mask the claim"
else
  fail "tool-only trailing event does not mask the claim"
fi

# An evidenced transcript message stays silent end-to-end.
{
  jq -nc '{type:"assistant", message:{content:[{type:"text", text:"All tests pass.\n\n## Evidence Block\nCommand: npm test\nExit code: 0\nTail (last 3 lines):\n  ok"}]}}'
} > "$TR"
out=$(jq -nc --arg t "$TR" '{transcript_path: $t}' | bash "$HOOK" 2>&1)
if [ -z "$out" ]; then
  pass "transcript fallback honors an Evidence Block"
else
  fail "transcript fallback honors an Evidence Block (got: $out)"
fi

# ===== safety.json bypass =====
mkdir -p "$TMPDIR_BASE/byp/.geniro"
echo '{"allow_patterns":["evidence-stop"]}' > "$TMPDIR_BASE/byp/.geniro/safety.json"
cd "$TMPDIR_BASE/byp" || exit 1
out=$(run_msg 'All tests pass, ready to ship.')
if [ -z "$out" ]; then
  pass "evidence-stop bypass silences the warning"
else
  fail "evidence-stop bypass silences the warning (got: $out)"
fi
cd "$TMPDIR_BASE" || exit 1

echo
echo "Tests run: $TESTS_RUN, failed: $TESTS_FAILED"
[ "$TESTS_FAILED" -eq 0 ]
