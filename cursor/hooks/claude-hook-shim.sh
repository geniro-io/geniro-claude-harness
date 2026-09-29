#!/usr/bin/env bash
# claude-hook-shim.sh — run one of the plugin's Claude Code hook scripts under
# Cursor's hook runtime.
#
# Cursor and Claude Code speak different hook dialects: event names
# (beforeShellExecution vs PreToolUse/Bash), stdin payload shape
# ({command, cwd} vs {tool_name, tool_input}), and verdict signalling
# (JSON {"permission":...} vs exit code + stderr). The hook scripts in
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
#   other permission hook -> script not run, answered {"permission":"allow"}
#   anything else         -> no-op (exit 0)
#
# The shim moves into the payload's cwd before running the script: hooks
# resolve the project root, .geniro/ state, and safety.json by walking up from
# the process cwd, which under Cursor is wherever the editor launched the hook.
#
# Verdict translation: script exit 2 (Claude Code "block") becomes
# {"permission":"deny","agent_message":<script stderr>} + exit 0, so the block
# reason reaches the Cursor agent instead of being dropped. Exit 0 becomes
# {"permission":"allow"}, carrying the script's stdout notice (systemMessage)
# as agent_message when it printed one. Any other exit passes through
# unchanged, so the hooks.json entry's failClosed decides, as it does for a
# timeout. A payload the shim cannot parse gets no answer at all.
set -uo pipefail

SHIM_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "$SHIM_DIR/../.." && pwd)"
export CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT"

SCRIPT_NAME="${1:-}"
SCRIPT=""
case "$SCRIPT_NAME" in
  ""|*/*) ;; # basenames only — the shim runs nothing outside hooks/
  *) [ -f "$PLUGIN_ROOT/hooks/$SCRIPT_NAME" ] && SCRIPT="$PLUGIN_ROOT/hooks/$SCRIPT_NAME" ;;
esac

INPUT="$(cat 2>/dev/null || true)"

# Cursor takes a permission hook's stdout as its verdict, and an exit 0 with no
# JSON, or with JSON that lacks a `permission` key, BLOCKS the action whatever
# the entry's failClosed says (cursor.com/docs/hooks, fetched 2026-09-29). So
# on these events every path that lets the action through answers "allow" out
# loud — including a script that no longer ships, which a profile installed
# from an older release still names. An explicit allow never outvotes another
# hook: Cursor merges deny over ask over allow.
PERMISSION_EVENTS="beforeShellExecution beforeMCPExecution beforeReadFile beforeTabFileRead subagentStart preToolUse"
is_permission_event() {
  [ -n "$1" ] && case " $PERMISSION_EVENTS " in *" $1 "*) true ;; *) false ;; esac
}

# jq is both the payload translator and the response writer, so without it the
# script cannot run at all. Say so out loud — each hook announces its own
# inactivity under Claude Code, and a silent allow would leave the user
# believing it is live. The event match is a plain glob and the answers are
# printf literals because the tool that would parse and format JSON is the one
# missing. SCRIPT_NAME is safe to embed: it is an existing hooks/ basename.
if ! command -v jq >/dev/null 2>&1; then
  EVENT=""
  for E in sessionStart $PERMISSION_EVENTS; do
    case "$INPUT" in *'"hook_event_name"'*"\"$E\""*) EVENT="$E"; break ;; esac
  done
  NOTICE="Geniro hook inactive: jq not found on PATH, so ${SCRIPT_NAME} is NOT running. Install jq to restore it."
  if [ -z "$SCRIPT" ]; then
    is_permission_event "$EVENT" && printf '{"permission":"allow"}\n'
  elif [ "$EVENT" = "sessionStart" ]; then
    printf '{"additional_context":"%s"}\n' "$NOTICE"
  elif [ "$EVENT" = "beforeShellExecution" ]; then
    printf '{"permission":"allow","agent_message":"%s"}\n' "$NOTICE"
  elif is_permission_event "$EVENT"; then
    printf '{"permission":"allow"}\n'
  fi
  exit 0
fi

EVENT="$(printf '%s' "$INPUT" | jq -r '.hook_event_name // ""' 2>/dev/null)" || exit 0

# allow [notice] — the answer for every path that lets the action through. Off
# a permission event there is no verdict to give, so nothing is printed.
allow() {
  is_permission_event "$EVENT" || exit 0
  jq -nc --arg m "${1:-}" '{permission: "allow"} + (if $m == "" then {} else {agent_message: $m} end)'
  exit 0
}

[ -n "$SCRIPT" ] || allow

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
    allow
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

# A here-string, not a pipe: RC must be the script's own exit status. Under
# pipefail a script that exits before draining stdin kills the writer with
# SIGPIPE, and that 141 would read as a crash.
STDOUT="$(bash "$SCRIPT" 2>"$STDERR_FILE" <<<"$PAYLOAD")"
RC=$?

if [ "$RC" -eq 2 ]; then
  jq -n --arg msg "$(cat "$STDERR_FILE" 2>/dev/null || true)" \
    '{permission: "deny", agent_message: (if $msg == "" then "Blocked by a Geniro guardrail." else $msg end)}'
  exit 0
fi

case "$EVENT" in
  sessionStart)
    [ -n "$STDOUT" ] || exit 0
    printf '%s' "$STDOUT" \
      | jq -c '{additional_context: (.hookSpecificOutput.additionalContext // "")} | select(.additional_context != "")' \
      2>/dev/null || true
    ;;
  beforeShellExecution)
    # A script that crashed has not checked the command, so its exit status
    # goes to Cursor untranslated.
    [ "$RC" -eq 0 ] || exit "$RC"
    allow "$(printf '%s' "$STDOUT" | jq -r '.systemMessage // ""' 2>/dev/null || true)"
    ;;
esac

exit 0
