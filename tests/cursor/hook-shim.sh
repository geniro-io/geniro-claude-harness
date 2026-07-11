#!/usr/bin/env bash
# Smoke test for cursor/hooks/claude-hook-shim.sh (Cursor -> Claude Code hook adapter).
#
# Run: bash tests/cursor/hook-shim.sh
#
# Coverage:
#   - beforeShellExecution with a destructive git command -> {"permission":"deny"} JSON.
#   - beforeShellExecution with a benign command -> no output, exit 0.
#   - preToolUse Write to a protected file, with Cursor's `path` alias key ->
#     deny (alias normalized to file_path).
#   - sessionStart -> Claude additionalContext re-emitted as additional_context.
#   - Unknown event -> no-op exit 0.
#   - Missing / path-traversal script argument -> no-op exit 0 (fail-open).
#   - cursor/hooks.json is valid JSON and every wired script exists in hooks/.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
SHIM="$REPO_ROOT/cursor/hooks/claude-hook-shim.sh"

TMPDIR_BASE="$(mktemp -d)"
ORIGINAL_PWD="$PWD"
trap 'cd "$ORIGINAL_PWD"; rm -rf "$TMPDIR_BASE"' EXIT
cd "$TMPDIR_BASE"

TESTS_RUN=0
TESTS_FAILED=0
pass() { TESTS_RUN=$((TESTS_RUN + 1)); echo "PASS: $1"; }
fail() { TESTS_RUN=$((TESTS_RUN + 1)); TESTS_FAILED=$((TESTS_FAILED + 1)); echo "FAIL: $1" >&2; }

# --- deny on destructive git ---
OUT="$(jq -nc '{hook_event_name:"beforeShellExecution", command:"git push --force origin main", cwd:"."}' \
  | bash "$SHIM" block-dangerous-git.sh)"
RC=$?
if [ "$RC" -eq 0 ] && [ "$(printf '%s' "$OUT" | jq -r '.permission' 2>/dev/null)" = "deny" ]; then
  pass "beforeShellExecution force-push -> permission deny"
else
  fail "beforeShellExecution force-push -> expected deny JSON, got rc=$RC out=$OUT"
fi
if printf '%s' "$OUT" | jq -e '.agent_message | length > 0' >/dev/null 2>&1; then
  pass "deny carries the guardrail reason in agent_message"
else
  fail "deny JSON missing agent_message"
fi

# --- benign command passes silently ---
OUT="$(jq -nc '{hook_event_name:"beforeShellExecution", command:"git status", cwd:"."}' \
  | bash "$SHIM" block-dangerous-git.sh)"
RC=$?
if [ "$RC" -eq 0 ] && [ -z "$OUT" ]; then
  pass "benign command -> silent allow"
else
  fail "benign command -> expected silent exit 0, got rc=$RC out=$OUT"
fi

# --- preToolUse with Cursor `path` alias hits file protection ---
OUT="$(jq -nc '{hook_event_name:"preToolUse", tool_name:"Write", tool_input:{path:".env"}, cwd:"."}' \
  | bash "$SHIM" file-protection.sh)"
RC=$?
if [ "$RC" -eq 0 ] && [ "$(printf '%s' "$OUT" | jq -r '.permission' 2>/dev/null)" = "deny" ]; then
  pass "preToolUse Write .env via path alias -> permission deny"
else
  fail "preToolUse Write .env -> expected deny JSON, got rc=$RC out=$OUT"
fi

# --- sessionStart re-emits additionalContext as additional_context ---
OUT="$(jq -nc --arg r "$TMPDIR_BASE" '{hook_event_name:"sessionStart", workspace_roots:[$r]}' \
  | bash "$SHIM" session-start-restore.sh)"
RC=$?
if [ "$RC" -eq 0 ]; then
  if [ -z "$OUT" ] || printf '%s' "$OUT" | jq -e 'has("additional_context")' >/dev/null 2>&1; then
    pass "sessionStart -> exit 0 with empty or additional_context JSON"
  else
    fail "sessionStart -> unexpected output shape: $OUT"
  fi
else
  fail "sessionStart -> expected exit 0, got rc=$RC"
fi

# --- unknown event is a no-op ---
OUT="$(jq -nc '{hook_event_name:"afterAgentThought"}' | bash "$SHIM" file-protection.sh)"
RC=$?
if [ "$RC" -eq 0 ] && [ -z "$OUT" ]; then
  pass "unknown event -> no-op"
else
  fail "unknown event -> expected silent exit 0, got rc=$RC out=$OUT"
fi

# --- missing and traversal script args fail open ---
OUT="$(jq -nc '{hook_event_name:"beforeShellExecution", command:"x"}' | bash "$SHIM")"
RC=$?
[ "$RC" -eq 0 ] && [ -z "$OUT" ] && pass "missing script arg -> no-op" \
  || fail "missing script arg -> expected silent exit 0, got rc=$RC out=$OUT"
OUT="$(jq -nc '{hook_event_name:"beforeShellExecution", command:"x"}' | bash "$SHIM" "../lib/hash.sh")"
RC=$?
[ "$RC" -eq 0 ] && [ -z "$OUT" ] && pass "path-traversal script arg -> no-op" \
  || fail "path-traversal script arg -> expected silent exit 0, got rc=$RC out=$OUT"

# --- cursor/hooks.json integrity ---
if jq -e '.version == 1 and (.hooks | type == "object")' "$REPO_ROOT/cursor/hooks.json" >/dev/null 2>&1; then
  pass "cursor/hooks.json is valid Cursor-schema JSON"
else
  fail "cursor/hooks.json invalid"
fi
MISSING=0
while IFS= read -r script; do
  [ -f "$REPO_ROOT/hooks/$script" ] || { MISSING=$((MISSING + 1)); echo "  missing: hooks/$script" >&2; }
done < <(jq -r '.hooks[][] | .command' "$REPO_ROOT/cursor/hooks.json" | awk '{print $2}')
if [ "$MISSING" -eq 0 ]; then
  pass "every script wired in cursor/hooks.json exists in hooks/"
else
  fail "$MISSING wired script(s) missing from hooks/"
fi

echo
echo "Tests run: $TESTS_RUN, failed: $TESTS_FAILED"
exit "$TESTS_FAILED"
