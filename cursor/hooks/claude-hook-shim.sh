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
#   preToolUse            -> tool_name passthrough (Shell->Bash), tool_input
#                            normalized so .file_path is present when Cursor
#                            used an alias key (path / target_file)
#   sessionStart          -> {source:"startup", cwd:<first workspace root>}
#                            output {hookSpecificOutput:{additionalContext}}
#                            re-emitted as Cursor's {additional_context}
#   anything else         -> no-op (exit 0)
#
# Exit-code translation: script exit 2 (Claude Code "block") becomes
# {"permission":"deny","agent_message":<script stderr>} + exit 0, so the block
# reason reaches the Cursor agent instead of being dropped. Any other failure
# fails open, matching the scripts' own fail-open contract.
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

command -v jq >/dev/null 2>&1 || exit 0

INPUT="$(cat 2>/dev/null || true)"
EVENT="$(printf '%s' "$INPUT" | jq -r '.hook_event_name // ""' 2>/dev/null || echo "")"

case "$EVENT" in
  beforeShellExecution)
    PAYLOAD="$(printf '%s' "$INPUT" | jq -c \
      '{tool_name: "Bash", tool_input: {command: (.command // "")}, cwd: (.cwd // "")}' \
      2>/dev/null)" || exit 0
    ;;
  preToolUse)
    PAYLOAD="$(printf '%s' "$INPUT" | jq -c '
      {
        tool_name: (if .tool_name == "Shell" then "Bash" else (.tool_name // "") end),
        tool_input: ((.tool_input // {}) +
          (if ((.tool_input.file_path // .tool_input.path // .tool_input.target_file // null) != null)
           then {file_path: (.tool_input.file_path // .tool_input.path // .tool_input.target_file)}
           else {} end)),
        cwd: (.cwd // "")
      }' 2>/dev/null)" || exit 0
    ;;
  sessionStart)
    PAYLOAD="$(printf '%s' "$INPUT" | jq -c \
      '{source: "startup", cwd: (.workspace_roots[0] // "")}' 2>/dev/null)" || exit 0
    ;;
  *)
    exit 0
    ;;
esac

STDERR_FILE="$(mktemp)"
trap 'rm -f "$STDERR_FILE"' EXIT
STDOUT="$(printf '%s' "$PAYLOAD" | bash "$SCRIPT" 2>"$STDERR_FILE")"
RC=$?
STDERR="$(cat "$STDERR_FILE" 2>/dev/null || true)"

if [ "$RC" -eq 2 ]; then
  jq -n --arg msg "$STDERR" \
    '{permission: "deny", agent_message: (if $msg == "" then "Blocked by a Geniro guardrail." else $msg end)}'
  exit 0
fi

if [ "$EVENT" = "sessionStart" ] && [ -n "$STDOUT" ]; then
  printf '%s' "$STDOUT" \
    | jq -c '{additional_context: (.hookSpecificOutput.additionalContext // "")} | select(.additional_context != "")' \
    2>/dev/null || true
fi

exit 0
