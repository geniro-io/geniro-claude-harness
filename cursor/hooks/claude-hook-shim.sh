#!/usr/bin/env bash
# claude-hook-shim.sh — run one of the plugin's Claude Code hook scripts under
# Cursor's hook runtime.
#
# Cursor and Claude Code speak different hook dialects: event names
# (beforeShellExecution vs PreToolUse/Bash), stdin payload shape
# ({command, cwd} vs {tool_name, tool_input}), and block signalling
# (JSON {"permission":"deny"} vs bare exit 2 + stderr). The hook scripts in
# hooks/ are written against the Claude Code dialect; this shim translates in
# both directions so the same scripts serve both runtimes with no fork.
#
# Usage (from cursor/hooks.json): ./cursor/hooks/claude-hook-shim.sh <script-basename>
#
# Translation map:
#   beforeShellExecution  -> {tool_name:"Bash", tool_input:{command}, cwd}
#   sessionStart          -> {source:"startup", cwd:<first workspace root>}
#                            output {hookSpecificOutput:{additionalContext}}
#                            re-emitted as Cursor's {additional_context}
#   anything else         -> no-op (exit 0)
#
# The shim moves into the payload's cwd before running the script: hooks
# resolve the project root, .geniro/ state, and safety.json by walking up from
# the process cwd, which under Cursor is wherever the editor launched the hook.
#
# Exit-code translation: script exit 2 (Claude Code "block") becomes
# {"permission":"deny","agent_message":<script stderr>} + exit 0, so the block
# reason reaches the Cursor agent instead of being dropped. A script's stdout
# notice (systemMessage) is re-emitted as {"agent_message":...} with no
# permission key — an informational notice must not vote on the action. Any
# other outcome, a malformed payload included, is a silent exit 0, matching the
# scripts' own fail-open contract.
set -uo pipefail

SHIM_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "$SHIM_DIR/../.." && pwd)"
export CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT"

SCRIPT_NAME="${1:-}"
[ -n "$SCRIPT_NAME" ] || exit 0
case "$SCRIPT_NAME" in
  */*) exit 0 ;; # basenames only — the shim runs nothing outside hooks/
esac
SCRIPT="$PLUGIN_ROOT/hooks/$SCRIPT_NAME"
[ -f "$SCRIPT" ] || exit 0

INPUT="$(cat 2>/dev/null || true)"

# jq is both the payload translator and the response writer, so without it the
# script cannot run at all. Say so out loud — each hook announces its own
# inactivity under Claude Code, and a silent exit 0 would leave the user
# believing it is live. The notice is a printf literal and the event match a
# plain glob because the tool that would parse and format JSON is the one
# missing. SCRIPT_NAME is safe to embed: it is an existing hooks/ basename.
if ! command -v jq >/dev/null 2>&1; then
  NOTICE="Geniro hook inactive: jq not found on PATH, so ${SCRIPT_NAME} is NOT running. Install jq to restore it."
  case "$INPUT" in
    *'"hook_event_name"'*'"sessionStart"'*)
      printf '{"additional_context":"%s"}\n' "$NOTICE" ;;
    *'"hook_event_name"'*'"beforeShellExecution"'*)
      printf '{"agent_message":"%s"}\n' "$NOTICE" ;;
  esac
  exit 0
fi

EVENT="$(printf '%s' "$INPUT" | jq -r '.hook_event_name // ""' 2>/dev/null)" || exit 0

case "$EVENT" in
  beforeShellExecution)
    PAYLOAD="$(printf '%s' "$INPUT" | jq -c \
      '{tool_name: "Bash", tool_input: {command: (.command // "")}, cwd: (.cwd // "")}' \
      2>/dev/null)" || exit 0
    ;;
  sessionStart)
    PAYLOAD="$(printf '%s' "$INPUT" | jq -c \
      '{source: "startup", cwd: (.workspace_roots[0] // "")}' 2>/dev/null)" || exit 0
    ;;
  *)
    exit 0
    ;;
esac

# Run the script from the directory the action targets — Cursor's own working
# directory is not the project root, so a per-project safety.json allowlist
# would otherwise be looked up in the wrong tree. Mirrors what
# session-start-restore.sh does with the payload's .cwd on the Claude Code side.
HOOK_CWD="$(printf '%s' "$PAYLOAD" | jq -r '.cwd // ""' 2>/dev/null || echo "")"
if [ -n "$HOOK_CWD" ] && [ -d "$HOOK_CWD" ]; then
  cd "$HOOK_CWD" || true
fi

# The script's stderr is the block reason. Without the /dev/null fallback a
# failed mktemp turns the `2>"$STDERR_FILE"` redirect below into an error that
# skips the script, so a guard would never run; with it, only the reason text
# is lost and the generic deny message covers that. The trap carries INT and
# TERM too: Cursor kills a hook that overruns its timeout, and a signal death
# skips an EXIT-only trap.
STDERR_FILE="$(mktemp 2>/dev/null || true)"
if [ -z "$STDERR_FILE" ] || [ ! -f "$STDERR_FILE" ]; then
  STDERR_FILE="/dev/null"
fi
trap '[ "$STDERR_FILE" = "/dev/null" ] || rm -f "$STDERR_FILE"' EXIT INT TERM

STDOUT="$(printf '%s' "$PAYLOAD" | bash "$SCRIPT" 2>"$STDERR_FILE")"
RC=$?

if [ "$RC" -eq 2 ]; then
  jq -n --arg msg "$(cat "$STDERR_FILE" 2>/dev/null || true)" \
    '{permission: "deny", agent_message: (if $msg == "" then "Blocked by a Geniro guardrail." else $msg end)}'
  exit 0
fi

[ -n "$STDOUT" ] || exit 0
case "$EVENT" in
  sessionStart)
    printf '%s' "$STDOUT" \
      | jq -c '{additional_context: (.hookSpecificOutput.additionalContext // "")} | select(.additional_context != "")' \
      2>/dev/null || true
    ;;
  beforeShellExecution)
    printf '%s' "$STDOUT" \
      | jq -c '{agent_message: (.systemMessage // "")} | select(.agent_message != "")' \
      2>/dev/null || true
    ;;
esac

exit 0
