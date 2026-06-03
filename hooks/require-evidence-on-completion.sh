#!/usr/bin/env bash
# require-evidence-on-completion.sh — Stop hook, WARN-ONLY (exit 0 + stderr).
# Scans the last assistant message for forbidden completion phrases without an Evidence Block.
# Per audit revision M2: Stop hooks fire ~50-80% of the time; treat as soft reminder layer, not enforcement.
# Bypass: .geniro/safety.json allow_patterns: ["evidence-stop"].
#
# Known limitations (DELIBERATE — not bugs):
#  - The `file:line` citation shortcut (regex matches any `path.ext:N`) lets
#    arbitrary path references defeat the warning. Documented as deliberate
#    soft-layer behavior — Stop hooks fire ~50-80% of the time per
#    multi-framework data; treat as soft reminder, not enforcement gate.
#
# Simplified 2026-05-10 — dropped uncertainty markers (`should`/`probably`/
# `seems to`) which produced high false positives on benign sentences
# ("I should clarify", "Should I run tests?"). Now scans only unambiguous
# completion claims.
set -euo pipefail

# Consume stdin - REQUIRED first step
INPUT=$(cat)

# Extract last_assistant_message (Anthropic Agent SDK StopHookInput optional field)
MSG=$(echo "$INPUT" | jq -r '.last_assistant_message // ""' 2>/dev/null || echo "")

# Fallback: parse transcript_path JSONL for the last assistant turn's text
if [ -z "$MSG" ]; then
  TRANSCRIPT_PATH=$(echo "$INPUT" | jq -r '.transcript_path // ""' 2>/dev/null || echo "")
  if [ -n "$TRANSCRIPT_PATH" ] && [ -f "$TRANSCRIPT_PATH" ]; then
    # Walk the JSONL file from the bottom; pick the last assistant turn's text content.
    # Each line is one event; assistant turns have type=="assistant" and message.content[].type=="text".
    # `tac` is GNU-only; stock macOS has `tail -r`. Fall back so the transcript
    # path is not silently disabled on macOS (which would defeat this warning).
    MSG=$({ tac "$TRANSCRIPT_PATH" 2>/dev/null || tail -r "$TRANSCRIPT_PATH" 2>/dev/null; } \
      | jq -r 'select(.type == "assistant") | .message.content[]? | select(.type == "text") | .text' 2>/dev/null \
      | head -1 || echo "")
  fi
fi

# Genuine tool-only ending — nothing to scan, exit silently
if [ -z "$MSG" ]; then
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
  *" evidence-stop "*) exit 0 ;;
esac

# False-positive mitigations: strip fenced code blocks and blockquoted lines.
# 1. Strip ```...``` fenced blocks (greedy across lines).
# 2. Strip lines starting with "> " (blockquotes).
SCAN=$(printf '%s' "$MSG" \
  | awk 'BEGIN{infence=0} /^[[:space:]]*```/{infence=!infence; next} !infence{print}' \
  | grep -vE '^[[:space:]]*>[[:space:]]' || true)

# Drop lines that end with `?` (interrogatives — questions, not claims).
SCAN=$(printf '%s\n' "$SCAN" | grep -vE '\?[[:space:]]*$' || true)

if [ -z "$SCAN" ]; then
  exit 0
fi

# Check for Evidence Block presence: requires both "## Evidence Block" + "Command:" + "Exit code:".
HAS_EVIDENCE=0
if printf '%s' "$SCAN" | grep -qE '^##[[:space:]]+Evidence Block[[:space:]]*$' \
   && printf '%s' "$SCAN" | grep -qE '^[[:space:]]*Command:' \
   && printf '%s' "$SCAN" | grep -qE '^[[:space:]]*Exit code:'; then
  HAS_EVIDENCE=1
fi

# Alternate evidence: file:line citation (e.g., src/foo.ts:42 or src/foo.ts:42-58).
if [ "$HAS_EVIDENCE" -eq 0 ]; then
  if printf '%s' "$SCAN" | grep -qE '[A-Za-z0-9_./-]+\.[A-Za-z0-9]+:[0-9]+(-[0-9]+)?'; then
    HAS_EVIDENCE=1
  fi
fi

# If evidence is present, exit silently
if [ "$HAS_EVIDENCE" -eq 1 ]; then
  exit 0
fi

# Forbidden phrase patterns — sentence-anchored where applicable.
# Each entry: an ERE regex (POSIX) and a human-readable label.
FOUND_PHRASE=""

# Sentence-boundary pattern prefix/suffix:
#   start-of-string OR sentence terminator + space
SB_START='(^|[.!?][[:space:]])'
SB_END='([[:space:]]|[.!?]|$)'

# Performative success — match as standalone exclamations
if printf '%s' "$SCAN" | grep -qiE "${SB_START}Great!"; then
  FOUND_PHRASE="Great!"
elif printf '%s' "$SCAN" | grep -qiE "${SB_START}Perfect!"; then
  FOUND_PHRASE="Perfect!"
elif printf '%s' "$SCAN" | grep -qiE "${SB_START}Done!"; then
  FOUND_PHRASE="Done!"
# Completion claim phrases
elif printf '%s' "$SCAN" | grep -qiE 'ready[[:space:]]+to[[:space:]]+ship'; then
  FOUND_PHRASE="ready to ship"
elif printf '%s' "$SCAN" | grep -qiE 'all[[:space:]]+tests[[:space:]]+pass'; then
  FOUND_PHRASE="all tests pass"
elif printf '%s' "$SCAN" | grep -qiE 'validation[[:space:]]+complete'; then
  FOUND_PHRASE="validation complete"
elif printf '%s' "$SCAN" | grep -qiE "${SB_START}shipped${SB_END}"; then
  FOUND_PHRASE="shipped"
fi

if [ -n "$FOUND_PHRASE" ]; then
  cat >&2 <<EOF
[evidence-stop] Warning: completion-claim phrase detected ("$FOUND_PHRASE") without an Evidence Block.
Per skills/_shared/evidence-standard.md, every completion claim ("done", "passing", "validated",
"shipped", "ready to ship") MUST be followed by an Evidence Block in the same message:

  ## Evidence Block
  Command: <verbatim command>
  Exit code: <integer>
  Tail (last 3 lines):
    <line N-2>
    <line N-1>
    <line N>

This is a soft reminder layer (Stop hooks fire ~50-80% of the time). Authoritative enforcement is
per-skill (reviewer-agent finding emit-time, verification-cache invalidation, Edit|Write TDD-order).
Bypass this warning by adding "evidence-stop" to .geniro/safety.json allow_patterns.
EOF
fi

# Warn-only: always exit 0 (per audit revision M2 — Stop hook is reminder, not enforcement)
exit 0
