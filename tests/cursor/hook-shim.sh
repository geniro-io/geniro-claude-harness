#!/usr/bin/env bash
# Smoke test for cursor/hooks/claude-hook-shim.sh (Cursor -> Claude Code hook adapter).
#
# Run: bash tests/cursor/hook-shim.sh
#
# Coverage:
#   - beforeShellExecution: every guard wired on that event denies its own
#     destructive command and stays silent on the benign counterpart.
#   - beforeShellExecution with a benign command -> no output, exit 0.
#   - preToolUse file-path aliases (path / target_file) -> deny.
#   - preToolUse content aliases (content / contents / code_edit / new_string /
#     new_source) -> the security scan still sees the content and denies; the
#     MultiEdit edits[] payload (no content key) keeps working.
#   - The payload's cwd is where the guards run: a project-rooted payload fires
#     the project's TDD gate even when the shim's own cwd is elsewhere.
#   - sessionStart -> Claude additionalContext re-emitted as additional_context.
#   - A hook's stdout systemMessage -> agent_message on the shell/edit events.
#   - jq missing -> loud Cursor-shaped notice instead of a silent fail-open.
#   - Unknown event -> no-op exit 0.
#   - Missing / path-traversal script argument -> no-op exit 0 (fail-open).
#   - cursor/hooks.json is valid JSON and every wired script exists in hooks/.

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

# Verdict of one shim run: "deny", "allow" (no output), or "malformed".
verdict() {
  local out="$1"
  if [ -z "$out" ]; then
    echo "allow"
    return 0
  fi
  printf '%s' "$out" | jq -r '.permission // "allow"' 2>/dev/null || echo "malformed"
}

# shell_verdict <script> <command> [cwd]
shell_verdict() {
  local out
  out="$(jq -nc --arg c "$2" --arg w "${3:-.}" \
    '{hook_event_name:"beforeShellExecution", command:$c, cwd:$w}' \
    | bash "$SHIM" "$1")"
  verdict "$out"
}

# edit_verdict <script> <tool_input-json> [cwd] [tool_name]
edit_verdict() {
  local out
  out="$(jq -nc --argjson ti "$2" --arg w "${3:-.}" --arg tn "${4:-Write}" \
    '{hook_event_name:"preToolUse", tool_name:$tn, tool_input:$ti, cwd:$w}' \
    | bash "$SHIM" "$1")"
  verdict "$out"
}

expect_verdict() { # <label> <expected> <actual>
  if [ "$3" = "$2" ]; then pass "$1"; else fail "$1 (expected $2, got $3)"; fi
}

# An anti-pattern the security scan must catch, assembled at runtime so this
# test file is not itself a match for the guard that scans edits.
EVAL_SNIPPET="ev""al(userInput)"

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

# --- every other guard wired on beforeShellExecution fires through the shim ---
expect_verdict ".geniro/ bulk delete -> deny" deny \
  "$(shell_verdict block-geniro-deletion.sh 'rm -rf .geniro/')"
expect_verdict "single-file .geniro/ delete -> allow" allow \
  "$(shell_verdict block-geniro-deletion.sh 'rm -f .geniro/planning/task/notes.md')"

expect_verdict "shell write to .env -> deny" deny \
  "$(shell_verdict file-protection.sh 'echo TOKEN=1 > .env')"
expect_verdict "shell write to a normal file -> allow" allow \
  "$(shell_verdict file-protection.sh 'echo hello > notes.txt')"

expect_verdict "shell write to a state path -> deny" deny \
  "$(shell_verdict enforce-state-helper.sh 'echo body > .geniro/planning/task/state.md')"
expect_verdict "state write through the atomic helper -> allow" allow \
  "$(shell_verdict enforce-state-helper.sh 'atomic_state_write .geniro/planning/task/state.md')"

expect_verdict "shell-authored anti-pattern -> deny" deny \
  "$(shell_verdict security-pattern-check.sh "printf '$EVAL_SNIPPET' > app.js")"
expect_verdict "shell-authored benign content -> allow" allow \
  "$(shell_verdict security-pattern-check.sh "printf 'const a = 1;' > app.js")"

# --- preToolUse with Cursor `path` alias hits file protection ---
OUT="$(jq -nc '{hook_event_name:"preToolUse", tool_name:"Write", tool_input:{path:".env"}, cwd:"."}' \
  | bash "$SHIM" file-protection.sh)"
RC=$?
if [ "$RC" -eq 0 ] && [ "$(printf '%s' "$OUT" | jq -r '.permission' 2>/dev/null)" = "deny" ]; then
  pass "preToolUse Write .env via path alias -> permission deny"
else
  fail "preToolUse Write .env -> expected deny JSON, got rc=$RC out=$OUT"
fi
expect_verdict "preToolUse Write .env via target_file alias -> deny" deny \
  "$(edit_verdict file-protection.sh '{"target_file":".env"}')"

# --- preToolUse content aliases reach the security scan ---
# The guard reads .content / .new_string / .new_source; a Cursor payload naming
# the edited content anything else used to arrive empty and be allowed.
if command -v perl >/dev/null 2>&1; then
  for key in content contents code_edit new_string new_source; do
    TI="$(jq -nc --arg k "$key" --arg v "$EVAL_SNIPPET" '{file_path:"a.js"} + {($k): $v}')"
    expect_verdict "preToolUse content key '$key' -> security scan denies" deny \
      "$(edit_verdict security-pattern-check.sh "$TI")"
  done
  TI="$(jq -nc --arg v "$EVAL_SNIPPET" '{target_file:"a.js", code_edit:$v}')"
  expect_verdict "preToolUse target_file+code_edit (pure Cursor payload) -> deny" deny \
    "$(edit_verdict security-pattern-check.sh "$TI")"
  TI="$(jq -nc --arg v "$EVAL_SNIPPET" '{file_path:"a.js", edits:[{old_string:"x", new_string:$v}]}')"
  expect_verdict "preToolUse MultiEdit edits[] still scanned -> deny" deny \
    "$(edit_verdict security-pattern-check.sh "$TI" "." MultiEdit)"
  expect_verdict "preToolUse benign content -> allow" allow \
    "$(edit_verdict security-pattern-check.sh '{"target_file":"a.js","code_edit":"const a = 1;"}')"
else
  skip "content-alias security cases (perl not installed — the scan self-skips)"
fi

# --- the payload's cwd is where the guards look for project state ---
# Guards walk up from their process cwd to find .geniro/; Cursor starts the hook
# elsewhere, so the shim must move into the payload's cwd first. A RED TDD cycle
# in a throwaway project is the cheapest observable: the gate can only fire if
# the state file was found.
if command -v git >/dev/null 2>&1; then
  PROJ="$TMPDIR_BASE/proj"
  mkdir -p "$PROJ/.geniro/state/tdd" "$PROJ/src" "$PROJ/tests"
  git -C "$PROJ" init -q >/dev/null 2>&1
  git -C "$PROJ" symbolic-ref HEAD refs/heads/cursor-shim-cwd >/dev/null 2>&1
  printf '## phase\nRED\n' > "$PROJ/.geniro/state/tdd/state-cursor-shim-cwd.md"
  BRANCH="$(git -C "$PROJ" branch --show-current 2>/dev/null || echo "")"
  if [ "$BRANCH" = "cursor-shim-cwd" ]; then
    expect_verdict "preToolUse production write during RED, shim cwd outside the project -> deny" deny \
      "$(edit_verdict enforce-tdd-order.sh "$(jq -nc --arg p "$PROJ/src/app.js" '{file_path:$p}')" "$PROJ")"
    expect_verdict "preToolUse test-file write during RED -> allow" allow \
      "$(edit_verdict enforce-tdd-order.sh "$(jq -nc --arg p "$PROJ/tests/app.test.js" '{file_path:$p}')" "$PROJ")"
    expect_verdict "beforeShellExecution production write during RED -> deny" deny \
      "$(shell_verdict enforce-tdd-order.sh 'printf x > src/app.js' "$PROJ")"
    expect_verdict "beforeShellExecution test-file write during RED -> allow" allow \
      "$(shell_verdict enforce-tdd-order.sh 'printf x > tests/app.test.js' "$PROJ")"
    expect_verdict "same production write with no project cwd -> allow (gate not in scope)" allow \
      "$(edit_verdict enforce-tdd-order.sh "$(jq -nc --arg p "$PROJ/src/app.js" '{file_path:$p}')" "$TMPDIR_BASE")"
  else
    skip "cwd-fold cases (could not pin the fixture branch name)"
  fi
else
  skip "cwd-fold cases (git not installed)"
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

# --- a hook's stdout notice reaches the Cursor agent on the shell/edit events ---
# Exercised against a copy of the shim rooted on a throwaway tree, so the notice
# comes from a stub hook rather than depending on a shipped guard emitting one.
FAKE_ROOT="$TMPDIR_BASE/fake-plugin"
mkdir -p "$FAKE_ROOT/cursor/hooks" "$FAKE_ROOT/hooks"
cp "$SHIM" "$FAKE_ROOT/cursor/hooks/claude-hook-shim.sh"
cat > "$FAKE_ROOT/hooks/notice-only.sh" <<'STUB'
#!/usr/bin/env bash
cat >/dev/null
printf '{"systemMessage":"Geniro test notice"}\n'
exit 0
STUB
for EV in beforeShellExecution preToolUse; do
  OUT="$(jq -nc --arg e "$EV" \
    '{hook_event_name:$e, command:"ls", tool_name:"Write", tool_input:{file_path:"a.js"}, cwd:"."}' \
    | bash "$FAKE_ROOT/cursor/hooks/claude-hook-shim.sh" notice-only.sh)"
  if [ "$(printf '%s' "$OUT" | jq -r '.agent_message' 2>/dev/null)" = "Geniro test notice" ]; then
    pass "$EV -> hook systemMessage forwarded as agent_message"
  else
    fail "$EV -> expected the hook notice in agent_message, got: $OUT"
  fi
  if printf '%s' "$OUT" | jq -e 'has("permission")' >/dev/null 2>&1; then
    fail "$EV notice must not carry a permission verdict (it would vote on the action)"
  else
    pass "$EV notice carries no permission verdict"
  fi
done

# --- jq missing -> loud notice, not a silent fail-open ---
STUB_BIN="$TMPDIR_BASE/nojq-bin"
mkdir -p "$STUB_BIN"
STUB_OK=1
for B in bash cat dirname; do
  BP="$(command -v "$B" 2>/dev/null || echo "")"
  if [ -z "$BP" ]; then STUB_OK=0; break; fi
  ln -sf "$BP" "$STUB_BIN/$B"
done
if [ "$STUB_OK" -eq 1 ]; then
  OUT="$(jq -nc '{hook_event_name:"beforeShellExecution", command:"git push --force", cwd:"."}' \
    | PATH="$STUB_BIN" bash "$SHIM" block-dangerous-git.sh)"
  if printf '%s' "$OUT" | jq -e '.agent_message | test("jq not found")' >/dev/null 2>&1; then
    pass "jq missing on beforeShellExecution -> agent_message names the inactive guard"
  else
    fail "jq missing on beforeShellExecution -> expected a loud notice, got: $OUT"
  fi
  OUT="$(jq -nc '{hook_event_name:"preToolUse", tool_name:"Write", tool_input:{path:".env"}, cwd:"."}' \
    | PATH="$STUB_BIN" bash "$SHIM" file-protection.sh)"
  if printf '%s' "$OUT" | jq -e '.agent_message | test("jq not found")' >/dev/null 2>&1; then
    pass "jq missing on preToolUse -> agent_message names the inactive guard"
  else
    fail "jq missing on preToolUse -> expected a loud notice, got: $OUT"
  fi
  OUT="$(jq -nc '{hook_event_name:"sessionStart", workspace_roots:["."]}' \
    | PATH="$STUB_BIN" bash "$SHIM" session-start-restore.sh)"
  if printf '%s' "$OUT" | jq -e '.additional_context | test("jq not found")' >/dev/null 2>&1; then
    pass "jq missing on sessionStart -> notice arrives as additional_context"
  else
    fail "jq missing on sessionStart -> expected a loud notice, got: $OUT"
  fi
  OUT="$(jq -nc '{hook_event_name:"afterAgentThought"}' \
    | PATH="$STUB_BIN" bash "$SHIM" file-protection.sh)"
  if [ -z "$OUT" ]; then
    pass "jq missing on an unhandled event -> still a silent no-op"
  else
    fail "jq missing on an unhandled event -> expected no output, got: $OUT"
  fi
else
  skip "jq-missing cases (could not build a jq-free PATH stub)"
fi

# --- jq missing but grep/sed/mktemp present -> the guard's own coarse
# fail-closed scan still denies through the shim. The stub above (bash/cat/
# dirname only) omits grep and mktemp, so neither the guards' jqless raw-text
# scan nor the shim's own mktemp can run there — that gap is exactly why a
# broken shim mktemp (T0 #3) went uncaught. This stub adds grep, sed and
# mktemp so both paths actually execute, and asserts the coarse scan's verdict
# reaches the Cursor agent as permission:"deny".
STUB_BIN2="$TMPDIR_BASE/nojq-full-bin"
mkdir -p "$STUB_BIN2"
STUB2_OK=1
for B in bash cat dirname grep sed mktemp rm; do
  BP="$(command -v "$B" 2>/dev/null || echo "")"
  if [ -z "$BP" ]; then STUB2_OK=0; break; fi
  ln -sf "$BP" "$STUB_BIN2/$B"
done
if [ "$STUB2_OK" -eq 1 ]; then
  OUT="$(jq -nc '{hook_event_name:"beforeShellExecution", command:"git push --force origin main", cwd:"."}' \
    | PATH="$STUB_BIN2" bash "$SHIM" block-dangerous-git.sh)"
  if printf '%s' "$OUT" | jq -e '.permission == "deny"' >/dev/null 2>&1; then
    pass "jq missing (grep/mktemp present), force-push -> coarse scan denies through the shim"
  else
    fail "jq missing (grep/mktemp present), force-push -> expected deny, got: $OUT"
  fi

  OUT="$(jq -nc '{hook_event_name:"beforeShellExecution", command:"rm -rf .geniro", cwd:"."}' \
    | PATH="$STUB_BIN2" bash "$SHIM" block-geniro-deletion.sh)"
  if printf '%s' "$OUT" | jq -e '.permission == "deny"' >/dev/null 2>&1; then
    pass "jq missing (grep/mktemp present), rm -rf .geniro -> coarse scan denies through the shim"
  else
    fail "jq missing (grep/mktemp present), rm -rf .geniro -> expected deny, got: $OUT"
  fi

  OUT="$(jq -nc '{hook_event_name:"beforeShellExecution", command:"echo TOKEN=1 > .env", cwd:"."}' \
    | PATH="$STUB_BIN2" bash "$SHIM" file-protection.sh)"
  if printf '%s' "$OUT" | jq -e '.permission == "deny"' >/dev/null 2>&1; then
    pass "jq missing (grep/mktemp present), .env write -> coarse scan denies through the shim"
  else
    fail "jq missing (grep/mktemp present), .env write -> expected deny, got: $OUT"
  fi
else
  skip "jq-missing-but-grep/sed/mktemp-present cases (could not build the stub PATH)"
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
