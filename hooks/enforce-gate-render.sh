#!/usr/bin/env bash
# enforce-gate-render.sh — PreToolUse AskUserQuestion, HARD-BLOCK (exit 2).
# Blocks a gate question that references content "above" when the current turn
# contains no visible assistant text — the user would be answering blind.
# Prompt-level render guards leak under drift; this is the mechanical backstop.
# Bypass: .geniro/safety.json allow_patterns: ["gate-render"].
set -euo pipefail

# Fail open but LOUDLY if jq is missing: without it the hook cannot parse tool
# input, and a silent exit 0 would leave the user believing the gate is active.
if ! command -v jq >/dev/null 2>&1; then
  printf '{"systemMessage":"Geniro hook inactive: jq not found on PATH, so the gate-render guard is NOT running. Install jq to restore it."}\n'
  exit 0
fi

# Consume stdin - REQUIRED first step
INPUT=$(cat)

# Defensive: only AskUserQuestion is in scope (the matcher should guarantee this).
TOOL_NAME=$(printf '%s' "$INPUT" | jq -r '.tool_name // ""' 2>/dev/null || echo "")
if [ -n "$TOOL_NAME" ] && [ "$TOOL_NAME" != "AskUserQuestion" ]; then
  exit 0
fi

# Bypass: read .geniro/safety.json walking up from cwd
find_safety_json() {
  local dir="$PWD"
  while [ "$dir" != "/" ]; do
    if [ -f "$dir/.geniro/safety.json" ]; then
      echo "$dir/.geniro/safety.json"
      return 0
    fi
    dir=$(dirname "$dir")
  done
  return 1
}

ALLOWED=""
SAFETY_FILE=$(find_safety_json 2>/dev/null || true)
if [ -n "$SAFETY_FILE" ] && [ -f "$SAFETY_FILE" ]; then
  ALLOWED=$(jq -r '.allow_patterns[]? // empty' "$SAFETY_FILE" 2>/dev/null | tr '\n' ' ' || echo "")
fi

case " $ALLOWED " in
  *" gate-render "*) exit 0 ;;
esac

# Concatenate every question surface the user will see: question text, option
# labels, option descriptions.
QTEXT=$(printf '%s' "$INPUT" | jq -r '
  [.tool_input.questions[]?
    | (.question // ""), (.options[]?.label // ""), (.options[]?.description // "")]
  | join(" ")' 2>/dev/null || echo "")

# Only gate questions that point at content "above" — templated gate questions
# do ("Full explanation above." / "Approve the spec summarized above?");
# legitimately-bare lean questions never reference "above".
if ! printf '%s' "$QTEXT" | grep -qiE '(^|[^[:alnum:]_])above([^[:alnum:]_]|$)'; then
  exit 0
fi

TRANSCRIPT_PATH=$(printf '%s' "$INPUT" | jq -r '.transcript_path // ""' 2>/dev/null || echo "")
# Fail open when the transcript is unavailable (old harness, stale path,
# permissions) — blocking on missing observability would break every gate.
if [ -z "$TRANSCRIPT_PATH" ] || [ ! -f "$TRANSCRIPT_PATH" ] || [ ! -r "$TRANSCRIPT_PATH" ]; then
  exit 0
fi

# Reverse-scan the transcript (newest first) and emit the first decisive verdict:
#   RENDER   — assistant record with non-whitespace text (string content, or a
#              content array with a non-whitespace text block): a visible
#              message exists in the current turn.
#   USERTEXT — real user message with non-whitespace text (same two shapes):
#              start of turn reached without a render.
# User records that are only tool_result blocks are mid-turn tool feedback;
# anything else (system, summary, progress, malformed line) is skipped via
# fromjson?/objects so one bad line never kills the stream. The 2000-record
# cap bounds work on huge transcripts; past it with no decision → fail open.
# `tac` is GNU-only; stock macOS has `tail -r`. Branch on availability rather
# than `tac || tail -r`: if tac dies mid-stream (SIGPIPE once jq's first() has
# its answer), the || fallback would re-feed the transcript from the start.
scan_transcript() {
  {
    if command -v tac >/dev/null 2>&1; then
      tac "$TRANSCRIPT_PATH" 2>/dev/null
    else
      tail -r "$TRANSCRIPT_PATH" 2>/dev/null
    fi
  } | jq -nRr '
        first(
          limit(2000; inputs)
          | fromjson?
          | objects
          | if .type == "assistant" then
              ((.message.content // null) as $c
               | if ($c | type) == "string" then
                   (if ($c | test("\\S")) then "RENDER" else empty end)
                 elif ($c | type) == "array" then
                   (if ([$c[]? | objects | select(.type == "text")
                         | (.text // "") | select(test("\\S"))] | length) > 0
                    then "RENDER" else empty end)
                 else empty end)
            elif .type == "user" then
              ((.message.content // null) as $c
               | if ($c | type) == "string" then
                   (if ($c | test("\\S")) then "USERTEXT" else empty end)
                 elif ($c | type) == "array" then
                   (if ([$c[]? | objects | select(.type == "text")
                         | (.text // "") | select(test("\\S"))] | length) > 0
                    then "USERTEXT" else empty end)
                 else empty end)
            else empty
            end
        )' 2>/dev/null || true
}

VERDICT=$(scan_transcript)
if [ "$VERDICT" != "USERTEXT" ]; then
  # "RENDER" (a visible message exists) or no decision (fail open).
  exit 0
fi

# The harness writes transcript lines with a lazy flush (~100ms); the in-flight
# turn's text block may not be on disk yet. Re-scan once before blocking.
sleep 0.4
VERDICT=$(scan_transcript)
if [ "$VERDICT" != "USERTEXT" ]; then
  exit 0
fi

cat >&2 <<'EOF'
Gate render missing: this question references content "above", but no visible assistant message exists in the current turn — the user would be answering blind.
This is an automated plugin guard (gate-render), NOT a user denial. Do not stop, and do not treat the question as answered.
Recovery: (1) write the full gate render as an ordinary chat message — the digest, evidence, and visuals the question refers to; (2) then call AskUserQuestion again with the same options.
Project bypass: add "gate-render" to allow_patterns in .geniro/safety.json.
EOF
exit 2
