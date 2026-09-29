#!/usr/bin/env bash
# Smoke test for cursor/hooks/claude-hook-shim.sh (Cursor -> Claude Code hook adapter).
#
# Run: bash tests/cursor/hook-shim.sh
#
# Coverage:
#   - beforeShellExecution through block-geniro-force-add.sh: a force-add on
#     .geniro/ -> permission deny carrying the guard's reason; a benign command
#     -> an explicit permission allow (Cursor blocks an exit 0 with no verdict).
#   - The payload's cwd is where the hook runs: a project's own safety.json
#     allowlist is honored even when the shim's own cwd is elsewhere.
#   - Payload translation both ways, against a stub hook that echoes what it
#     received: beforeShellExecution -> Bash tool_input, sessionStart ->
#     {source, cwd}; systemMessage -> agent_message on an allow, and
#     additionalContext -> additional_context.
#   - A script that crashes passes its exit status through, with no verdict.
#   - sessionStart through the real session-start-restore.sh.
#   - A failed mktemp still runs the guard and still denies.
#   - jq missing -> a Cursor-shaped inactivity notice, and the script NOT run.
#   - preToolUse -> allow, script not run; unknown events and malformed
#     payloads -> no output, script not run.
#   - Missing / nonexistent / path-traversal script argument -> allow on a
#     permission event, no output on sessionStart.
#   - cursor/hooks.json is valid, wires only events the shim translates, every
#     wired script exists, and the force-add entry fails closed.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
SHIM="$REPO_ROOT/cursor/hooks/claude-hook-shim.sh"

TMPDIR_BASE="$(mktemp -d)"
ORIGINAL_PWD="$PWD"
trap 'cd "$ORIGINAL_PWD" || true; rm -rf "$TMPDIR_BASE"' EXIT
cd "$TMPDIR_BASE" || exit 1

TESTS_RUN=0
TESTS_FAILED=0
pass() { TESTS_RUN=$((TESTS_RUN + 1)); echo "PASS: $1"; }
fail() { TESTS_RUN=$((TESTS_RUN + 1)); TESTS_FAILED=$((TESTS_FAILED + 1)); echo "FAIL: $1" >&2; }
skip() { echo "SKIP: $1"; }

# Verdict of one shim run: its permission key, "none" when it gave no verdict
# (which Cursor treats as a block on a permission hook), or "malformed".
verdict() {
  local out="$1"
  if [ -z "$out" ]; then
    echo "none"
    return 0
  fi
  printf '%s' "$out" | jq -r '.permission // "none"' 2>/dev/null || echo "malformed"
}

# shell_verdict <script> <command> [cwd]
shell_verdict() {
  local out
  out="$(jq -nc --arg c "$2" --arg w "${3:-.}" \
    '{hook_event_name:"beforeShellExecution", command:$c, cwd:$w}' \
    | bash "$SHIM" "$1")"
  verdict "$out"
}

expect_verdict() { # <label> <expected> <actual>
  if [ "$3" = "$2" ]; then pass "$1"; else fail "$1 (expected $2, got $3)"; fi
}

# --- deny on a force-add of .geniro/ ---
OUT="$(jq -nc '{hook_event_name:"beforeShellExecution", command:"git add -f .geniro/actions/x.md", cwd:"."}' \
  | bash "$SHIM" block-geniro-force-add.sh)"
RC=$?
if [ "$RC" -eq 0 ] && [ "$(printf '%s' "$OUT" | jq -r '.permission' 2>/dev/null)" = "deny" ]; then
  pass "beforeShellExecution force-add -> permission deny"
else
  fail "beforeShellExecution force-add -> expected deny JSON, got rc=$RC out=$OUT"
fi
if printf '%s' "$OUT" | jq -e '.agent_message | test("git-add-force-geniro")' >/dev/null 2>&1; then
  pass "deny carries the guard's reason (pattern ID) in agent_message"
else
  fail "deny JSON missing the guard's reason: $OUT"
fi

# --- benign command is allowed out loud ---
OUT="$(jq -nc '{hook_event_name:"beforeShellExecution", command:"git status", cwd:"."}' \
  | bash "$SHIM" block-geniro-force-add.sh)"
RC=$?
if [ "$RC" -eq 0 ] && [ "$OUT" = '{"permission":"allow"}' ]; then
  pass "benign command -> explicit permission allow"
else
  fail "benign command -> expected exit 0 with {\"permission\":\"allow\"}, got rc=$RC out=$OUT"
fi

# --- the payload's cwd is where the hook looks for project state ---
# The guard walks up from its process cwd to find .geniro/safety.json; Cursor
# starts the hook elsewhere, so the shim must move into the payload's cwd first.
# The allowlist only takes effect if the guard actually ran inside the project.
PROJ="$TMPDIR_BASE/proj"
mkdir -p "$PROJ/.geniro" "$TMPDIR_BASE/elsewhere"
printf '{"allow_patterns": ["git-add-force-geniro"]}\n' > "$PROJ/.geniro/safety.json"
expect_verdict "force-add with a project allowlist, payload cwd inside the project -> allow" allow \
  "$(shell_verdict block-geniro-force-add.sh 'git add -f .geniro/actions/x.md' "$PROJ")"
expect_verdict "same force-add, payload cwd outside the project -> deny (allowlist not found)" deny \
  "$(shell_verdict block-geniro-force-add.sh 'git add -f .geniro/actions/x.md' "$TMPDIR_BASE/elsewhere")"

# --- sessionStart through the real restore hook ---
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

# --- payload translation and output re-emit, against a stub hook ---
# A copy of the shim rooted on a throwaway tree runs a stub that echoes the
# payload it received back as both a notice and session context, and leaves a
# marker so a later case can prove the shim did NOT run it.
FAKE_ROOT="$TMPDIR_BASE/fake-plugin"
FAKE_SHIM="$FAKE_ROOT/cursor/hooks/claude-hook-shim.sh"
RAN="$FAKE_ROOT/hooks/ran"
mkdir -p "$FAKE_ROOT/cursor/hooks" "$FAKE_ROOT/hooks"
cp "$SHIM" "$FAKE_SHIM"
cat > "$FAKE_ROOT/hooks/echo-payload.sh" <<'STUB'
#!/usr/bin/env bash
: > "${BASH_SOURCE[0]%/*}/ran"
IN="$(cat)"
jq -nc --arg p "$IN" '{systemMessage: $p, hookSpecificOutput: {additionalContext: $p}}'
STUB

OUT="$(jq -nc --arg w "$PROJ" '{hook_event_name:"beforeShellExecution", command:"ls -la", cwd:$w}' \
  | bash "$FAKE_SHIM" echo-payload.sh)"
ECHOED="$(printf '%s' "$OUT" | jq -r '.agent_message // ""' 2>/dev/null)"
if [ "$(printf '%s' "$ECHOED" | jq -c '[.tool_name, .tool_input.command, .cwd]' 2>/dev/null)" \
     = "$(jq -nc --arg w "$PROJ" '["Bash", "ls -la", $w]')" ]; then
  pass "beforeShellExecution -> {tool_name:Bash, tool_input:{command}, cwd}; systemMessage -> agent_message"
else
  fail "beforeShellExecution translation wrong: $OUT"
fi
expect_verdict "a notice rides on an explicit allow" allow "$(verdict "$OUT")"

cat > "$FAKE_ROOT/hooks/crash.sh" <<'STUB'
#!/usr/bin/env bash
echo '{"systemMessage":"half-written"}'
exit 1
STUB
OUT="$(jq -nc '{hook_event_name:"beforeShellExecution", command:"ls", cwd:"."}' \
  | bash "$FAKE_SHIM" crash.sh)"
RC=$?
if [ "$RC" -eq 1 ] && [ -z "$OUT" ]; then
  pass "a crashed script -> its exit status passes through, no verdict (failClosed decides)"
else
  fail "a crashed script -> expected rc=1 and no output, got rc=$RC out=$OUT"
fi

OUT="$(jq -nc --arg r "$PROJ" '{hook_event_name:"sessionStart", workspace_roots:[$r, "/other"]}' \
  | bash "$FAKE_SHIM" echo-payload.sh)"
ECHOED="$(printf '%s' "$OUT" | jq -r '.additional_context // ""' 2>/dev/null)"
if [ "$(printf '%s' "$ECHOED" | jq -c '[.source, .cwd]' 2>/dev/null)" \
     = "$(jq -nc --arg r "$PROJ" '["startup", $r]')" ] \
   && ! printf '%s' "$OUT" | jq -e 'has("agent_message")' >/dev/null 2>&1; then
  pass "sessionStart -> {source:startup, cwd:<first root>}; additionalContext -> additional_context only"
else
  fail "sessionStart translation wrong: $OUT"
fi

# --- a failed mktemp still runs the guard and still denies ---
# Only the block's reason text is lost; the generic message stands in for it.
FAIL_BIN="$TMPDIR_BASE/failing-mktemp-bin"
mkdir -p "$FAIL_BIN"
printf '#!/bin/sh\nexit 1\n' > "$FAIL_BIN/mktemp"
chmod +x "$FAIL_BIN/mktemp"
OUT="$(jq -nc '{hook_event_name:"beforeShellExecution", command:"git add -f .geniro/x", cwd:"."}' \
  | PATH="$FAIL_BIN:$PATH" bash "$SHIM" block-geniro-force-add.sh)"
if [ "$(verdict "$OUT")" = "deny" ] \
   && [ "$(printf '%s' "$OUT" | jq -r '.agent_message' 2>/dev/null)" = "Blocked by a Geniro guardrail." ]; then
  pass "mktemp failure -> guard still runs, deny with the generic reason"
else
  fail "mktemp failure -> expected a generic deny, got: $OUT"
fi

# --- jq missing -> loud notice, and the script is not run ---
STUB_BIN="$TMPDIR_BASE/nojq-bin"
mkdir -p "$STUB_BIN"
STUB_OK=1
for B in bash cat dirname; do
  BP="$(command -v "$B" 2>/dev/null || echo "")"
  if [ -z "$BP" ]; then STUB_OK=0; break; fi
  ln -sf "$BP" "$STUB_BIN/$B"
done
if [ "$STUB_OK" -eq 1 ]; then
  OUT="$(jq -nc '{hook_event_name:"beforeShellExecution", command:"git add -f .geniro/x", cwd:"."}' \
    | PATH="$STUB_BIN" bash "$SHIM" block-geniro-force-add.sh)"
  if printf '%s' "$OUT" | jq -e '(.agent_message | test("jq not found") and test("block-geniro-force-add.sh")) and .permission == "allow"' >/dev/null 2>&1; then
    pass "jq missing on beforeShellExecution -> allow, agent_message names the inactive hook"
  else
    fail "jq missing on beforeShellExecution -> expected an allow carrying the notice, got: $OUT"
  fi
  OUT="$(jq -nc '{hook_event_name:"preToolUse", tool_name:"Shell"}' \
    | PATH="$STUB_BIN" bash "$SHIM" no-such-hook.sh)"
  if [ "$OUT" = '{"permission":"allow"}' ]; then
    pass "jq missing on a stale-profile permission entry -> bare allow"
  else
    fail "jq missing on a stale-profile permission entry -> expected a bare allow, got: $OUT"
  fi
  OUT="$(jq -nc '{hook_event_name:"sessionStart", workspace_roots:["."]}' \
    | PATH="$STUB_BIN" bash "$SHIM" session-start-restore.sh)"
  if printf '%s' "$OUT" | jq -e '.additional_context | test("jq not found")' >/dev/null 2>&1; then
    pass "jq missing on sessionStart -> notice arrives as additional_context"
  else
    fail "jq missing on sessionStart -> expected a notice, got: $OUT"
  fi
  OUT="$(jq -nc '{hook_event_name:"afterAgentThought"}' \
    | PATH="$STUB_BIN" bash "$SHIM" block-geniro-force-add.sh)"
  if [ -z "$OUT" ]; then
    pass "jq missing on an unhandled event -> still a silent no-op"
  else
    fail "jq missing on an unhandled event -> expected no output, got: $OUT"
  fi
  rm -f "$RAN"
  jq -nc '{hook_event_name:"beforeShellExecution", command:"ls", cwd:"."}' \
    | PATH="$STUB_BIN" bash "$FAKE_SHIM" echo-payload.sh >/dev/null
  if [ -e "$RAN" ]; then
    fail "jq missing -> the shim ran the script anyway"
  else
    pass "jq missing -> the script is not run"
  fi
else
  skip "jq-missing cases (could not build a jq-free PATH stub)"
fi

# --- events and payloads the shim does not translate never reach the script ---
# preToolUse included: nothing current is wired to it, so a Shell call arriving
# there must not be read as a Bash command — but a profile installed from an
# older release still wires it, and it is a permission hook, so it gets an
# allow. A payload the shim cannot parse gets no answer at all.
no_op_case() { # <label> <expected output> <raw payload>
  local out
  rm -f "$RAN"
  out="$(printf '%s' "$3" | bash "$FAKE_SHIM" echo-payload.sh)"
  if [ "$out" = "$2" ] && [ ! -e "$RAN" ]; then
    pass "$1 -> ${2:-no output}, script not run"
  else
    fail "$1 -> expected ${2:-no output} with the script not run, got out=$out ran=$([ -e "$RAN" ] && echo yes || echo no)"
  fi
}
no_op_case "preToolUse Shell call" '{"permission":"allow"}' \
  '{"hook_event_name":"preToolUse","tool_name":"Shell","tool_input":{"command":"git add -f .geniro/x"},"cwd":"."}'
no_op_case "unknown event" '' '{"hook_event_name":"afterAgentThought"}'
no_op_case "truncated payload" '' '{"hook_event_name":"beforeShellExecution","command":"git add -f .geniro/x"'
no_op_case "well-formed payload missing hook_event_name" '' '{"command":"git status"}'
no_op_case "empty payload" '' ''

# --- missing, nonexistent, and traversal script args run nothing ---
# The nonexistent case is a profile installed from an older release, still
# naming a script that no longer ships: on a permission hook it must allow, or
# Cursor blocks every command that entry sees.
SHELL_PAYLOAD="$(jq -nc '{hook_event_name:"beforeShellExecution", command:"x"}')"
START_PAYLOAD="$(jq -nc '{hook_event_name:"sessionStart", workspace_roots:["."]}')"
for ARG_CASE in "missing script arg|" "nonexistent script arg|no-such-hook.sh" "path-traversal script arg|../lib/hash.sh"; do
  LABEL="${ARG_CASE%%|*}"; ARG="${ARG_CASE#*|}"
  OUT="$(printf '%s' "$SHELL_PAYLOAD" | bash "$SHIM" ${ARG:+"$ARG"})"
  RC=$?
  if [ "$RC" -eq 0 ] && [ "$OUT" = '{"permission":"allow"}' ]; then
    pass "$LABEL on beforeShellExecution -> allow"
  else
    fail "$LABEL on beforeShellExecution -> expected exit 0 with an allow, got rc=$RC out=$OUT"
  fi
  OUT="$(printf '%s' "$START_PAYLOAD" | bash "$SHIM" ${ARG:+"$ARG"})"
  RC=$?
  if [ "$RC" -eq 0 ] && [ -z "$OUT" ]; then
    pass "$LABEL on sessionStart -> no output"
  else
    fail "$LABEL on sessionStart -> expected silent exit 0, got rc=$RC out=$OUT"
  fi
done

# --- cursor/hooks.json integrity ---
HOOKS_JSON="$REPO_ROOT/cursor/hooks.json"
if jq -e '.version == 1 and (.hooks | type == "object")' "$HOOKS_JSON" >/dev/null 2>&1; then
  pass "cursor/hooks.json is valid Cursor-schema JSON"
else
  fail "cursor/hooks.json invalid"
fi
MISSING=0
while IFS= read -r script; do
  [ -f "$REPO_ROOT/hooks/$script" ] || { MISSING=$((MISSING + 1)); echo "  missing: hooks/$script" >&2; }
done < <(jq -r '.hooks[][] | .command' "$HOOKS_JSON" | awk '{print $2}')
if [ "$MISSING" -eq 0 ]; then
  pass "every script wired in cursor/hooks.json exists in hooks/"
else
  fail "$MISSING wired script(s) missing from hooks/"
fi

# An entry on an event the shim does not translate is a silent no-op on every
# call — wire a new event only together with a translation branch for it.
UNTRANSLATED="$(jq -r '.hooks | keys[] | select(. != "beforeShellExecution" and . != "sessionStart")' "$HOOKS_JSON")"
if [ -z "$UNTRANSLATED" ]; then
  pass "cursor/hooks.json wires only events the shim translates"
else
  fail "cursor/hooks.json wires events the shim no-ops: $(printf '%s' "$UNTRANSLATED" | tr '\n' ' ')"
fi

# Cursor fails a hook OPEN on crash, timeout, or any non-2 exit unless the entry
# sets failClosed: true (cursor.com/docs/hooks, fetched 2026-09-23).
if [ "$(jq '[.hooks[][] | select((.command | test("block-geniro-force-add\\.sh")) and .failClosed == true)] | length' "$HOOKS_JSON")" = "1" ]; then
  pass "the force-add guard entry sets failClosed: true"
else
  fail "cursor/hooks.json must wire block-geniro-force-add.sh exactly once with failClosed: true"
fi

echo
echo "Tests run: $TESTS_RUN, failed: $TESTS_FAILED"
exit "$TESTS_FAILED"
