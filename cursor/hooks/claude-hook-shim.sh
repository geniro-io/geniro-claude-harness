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
#                            normalized so .file_path and .content are present
#                            when Cursor used an alias key (path / target_file;
#                            contents / code_edit / new_string / new_source)
#   sessionStart          -> {source:"startup", cwd:<first workspace root>}
#                            output {hookSpecificOutput:{additionalContext}}
#                            re-emitted as Cursor's {additional_context}
#   anything else         -> no-op (exit 0)
#
# The shim also moves into the payload's cwd before running the script: guards
# resolve the project root, .geniro/ state, and safety.json by walking up from
# the process cwd, which under Cursor is wherever the editor launched the hook.
#
# Exit-code translation: script exit 2 (Claude Code "block") becomes
# {"permission":"deny","agent_message":<script stderr>} + exit 0, so the block
# reason reaches the Cursor agent instead of being dropped. A script's stdout
# notice (systemMessage) is re-emitted as {"agent_message":...} with no
# permission key — an informational notice must not vote on an action another
# guard may deny. Any other failure fails open, matching the scripts' own
# fail-open contract.
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

# jq is both the payload reader and the response writer, so without it no guard
# can run. Say so out loud: every hook script announces its own inactivity on
# this path under Claude Code, and a silent exit 0 leaves the user believing all
# seven wired guards are live when they are inert. The notice is assembled with
# printf because the tool that would format JSON is the one that is missing —
# hence the fixed literal (nothing here needs escaping) and the plain-glob event
# detection.
if ! command -v jq >/dev/null 2>&1; then
  case "$SCRIPT_NAME" in
    *[!A-Za-z0-9._-]*) GUARD_NAME="a Geniro guard" ;;
    *) GUARD_NAME="$SCRIPT_NAME" ;;
  esac
  NOTICE="Geniro guard inactive: jq not found on PATH, so ${GUARD_NAME} is NOT running. Install jq to restore it."
  case "$INPUT" in
    *'"hook_event_name"'*'"sessionStart"'*)
      printf '{"additional_context":"%s"}\n' "$NOTICE" ;;
    *'"hook_event_name"'*'"beforeShellExecution"'*|*'"hook_event_name"'*'"preToolUse"'*)
      printf '{"agent_message":"%s"}\n' "$NOTICE" ;;
  esac
  exit 0
fi

EVENT="$(printf '%s' "$INPUT" | jq -r '.hook_event_name // ""' 2>/dev/null || echo "")"

case "$EVENT" in
  beforeShellExecution)
    PAYLOAD="$(printf '%s' "$INPUT" | jq -c \
      '{tool_name: "Bash", tool_input: {command: (.command // "")}, cwd: (.cwd // "")}' \
      2>/dev/null)" || exit 0
    ;;
  preToolUse)
    # Cursor names the edited path and the edited content with whichever key its
    # tool schema uses. The guards read `.file_path` (plus `.notebook_path`) and
    # `.content` / `.new_string` / `.new_source`, so an unrecognized alias makes
    # them see an empty target or empty content and allow the write. Fold both
    # families onto the canonical keys; the originals stay in tool_input so a
    # script reading them directly is unaffected.
    PAYLOAD="$(printf '%s' "$INPUT" | jq -c '
      (.tool_input // {}) as $ti
      | ($ti.file_path // $ti.path // $ti.target_file // "") as $fp
      | ($ti.content // $ti.contents // $ti.code_edit // $ti.new_string // $ti.new_source // "") as $ct
      | {
          tool_name: (if .tool_name == "Shell" then "Bash" else (.tool_name // "") end),
          tool_input: ($ti
            + (if ($fp | type) == "string" and $fp != "" then {file_path: $fp} else {} end)
            + (if ($ct | type) == "string" and $ct != "" then {content: $ct} else {} end)),
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

# Run the script from the directory the action targets. Each guard walks up from
# $PWD to find the project root, its .geniro/ state, and .geniro/safety.json;
# Cursor's own working directory is not that root, so without this move a
# project-scoped gate (a RED TDD cycle, a per-project allowlist) is looked up in
# the wrong tree and the guard silently allows. Mirrors what
# session-start-restore.sh does with the payload's .cwd on the Claude Code side.
HOOK_CWD="$(printf '%s' "$PAYLOAD" | jq -r '.cwd // ""' 2>/dev/null || echo "")"
if [ -n "$HOOK_CWD" ] && [ -d "$HOOK_CWD" ]; then
  cd "$HOOK_CWD" || true
fi

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

if [ -n "$STDOUT" ]; then
  case "$EVENT" in
    sessionStart)
      printf '%s' "$STDOUT" \
        | jq -c '{additional_context: (.hookSpecificOutput.additionalContext // "")} | select(.additional_context != "")' \
        2>/dev/null || true
      ;;
    beforeShellExecution|preToolUse)
      printf '%s' "$STDOUT" \
        | jq -c '{agent_message: (.systemMessage // "")} | select(.agent_message != "")' \
        2>/dev/null || true
      ;;
  esac
fi

exit 0
