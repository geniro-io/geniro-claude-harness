#!/usr/bin/env bash
# enforce-gate-render.sh — PreToolUse AskUserQuestion, HARD-BLOCK (exit 2).
# Blocks a gate question that needs a rendered chat block the user can see when
# the current turn contains no visible assistant text — the user would be
# answering blind. Catches BOTH a question that references content "above" AND
# one that carries finding-gate evidence shorthand without the "above" reference:
# a PRODUCT-DECISION tag, convergence wording, or a finding-ID (F5/M1b) when it
# is paired with finding-gate co-text (a parenthesized severity, or the words
# finding/reviewer/severity) — a bare finding-ID alone is too collision-prone.
# Prompt-level render guards leak under drift; this is the mechanical backstop.
# Also blocks a single call that batches >=2 product-decision findings as separate
# questions (the tabbed F3/F4/F5 prompt) — those resolve one finding per call.
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

# Proceed to the transcript scan when EITHER trigger matches; only when NEITHER
# does, exit 0 (unscanned). Two branches catch two ways a gate fires blind:
#   (a) the question points at content "above" — templated gate questions do
#       ("Full explanation above." / "Approve the spec summarized above?").
#   (b) the question carries finding-gate evidence shorthand without "above" —
#       a real /review open-decision gate fired with finding IDs and
#       convergence wording but no "above", so the (a)-only guard let it slip
#       (the recorded forbidden evasion: "strip the 'above' reference").
# Shorthand tokens are chosen for low false positives on benign lean questions:
# a PRODUCT-DECISION tag and convergence wording (converge/converged/
# convergence) fire on their own. A finding-ID token (uppercase F/M + digits +
# optional trailing lowercase letter, e.g. F5/F12/M1b — matched case-SENSITIVELY
# so stray lowercase words don't trip it) does NOT fire alone: a bare F/M-digit
# token collides with load-balancer models ("F5 load balancer"), function keys
# ("Press F5"), racing series ("F1 racing API"), version tags ("version M2"),
# branch names ("feature/F12-login"), and form fields ("form field F3"), so the
# token alone is not high-precision. It scans only with finding-gate co-text:
# a severity word immediately after an open paren (the way findings render
# severity, e.g. "(MEDIUM, security)"), OR the words finding/findings, reviewer,
# severity/severities. The co-text requirement is what keeps this branch's
# false-positive rate near zero while still catching a real open-decision gate
# like "F5 (MEDIUM, security): …". Bare severity words (HIGH / MEDIUM / LOW) are
# deliberately NOT a standalone trigger — they appear in too many benign
# questions (workspace-setup / review-depth choosers); they count only as
# co-text adjacent to a finding-ID + open paren. Legitimately-bare lean
# questions match no branch.
ABOVE_RE='(^|[^[:alnum:]_])above([^[:alnum:]_]|$)'
SHORTHAND_RE='(PRODUCT-DECISION|[Cc]onverg)'
FINDING_ID_RE='(^|[^[:alnum:]_])[FM][0-9]+[a-z]?([^[:alnum:]_]|$)'
FINDING_CTX_RE='\((CRITICAL|HIGH|MEDIUM|LOW)|finding|reviewer|severit'

# ===== Finding-batching guard (shape-based, render-independent) =====
# Product-decision gates resolve ONE finding per call (per review-handoff.md §3
# / per-finding-question.md §Single-finding gate). A call whose questions[] holds
# ≥2 entries that EACH read like a product-decision gate is the tabbed F3/F4/F5
# batch — block it regardless of render state, because no single chat render can
# precede a multi-finding call. The signal is per-question: count questions
# individually matching the same finding-gate shorthand the render guard uses
# (PRODUCT-DECISION / convergence, OR finding-ID + co-text). /plan's clarifying
# batch (≤4 questions carrying none of that) does not match.
QCOUNT=$(printf '%s' "$INPUT" | jq -r '.tool_input.questions | length' 2>/dev/null || echo 0)
if [ "${QCOUNT:-0}" -ge 2 ]; then
  # One line per question: its question text + option labels + descriptions, with
  # newlines flattened so each question stays on a single grep line.
  PER_Q=$(printf '%s' "$INPUT" | jq -r '
    .tool_input.questions[]?
    | ([(.question // ""), (.options[]?.label // ""), (.options[]?.description // "")] | join(" "))
    | gsub("[\n\r]+"; " ")' 2>/dev/null || echo "")
  DECISION_Q=0
  while IFS= read -r q_line; do
    [ -z "$q_line" ] && continue
    if printf '%s' "$q_line" | grep -qiE "$SHORTHAND_RE"; then
      DECISION_Q=$((DECISION_Q + 1))
    elif printf '%s' "$q_line" | grep -qE "$FINDING_ID_RE" \
      && printf '%s' "$q_line" | grep -qiE "$FINDING_CTX_RE"; then
      DECISION_Q=$((DECISION_Q + 1))
    fi
  done <<EOF_PERQ
$PER_Q
EOF_PERQ
  if [ "$DECISION_Q" -ge 2 ]; then
    cat >&2 <<'EOF'
Batched product-decision gate: this AskUserQuestion carries multiple findings as separate questions in one call (the tabbed F3/F4/F5 prompt). Product-decision findings are resolved one at a time — one AskUserQuestion call per finding, each preceded by its own rendered chat block with that finding's evidence and visual.
This is an automated plugin guard (gate-render), NOT a user denial. Do not treat the question as answered.
Recovery: fire one AskUserQuestion per finding in sequence — render finding 1 to chat, ask it, collect the answer, then render and ask finding 2, and so on.
Project bypass: add "gate-render" to allow_patterns in .geniro/safety.json.
EOF
    exit 2
  fi
fi

if   printf '%s' "$QTEXT" | grep -qiE "$ABOVE_RE"; then
  : # branch (a): references content "above" → scan
elif printf '%s' "$QTEXT" | grep -qiE "$SHORTHAND_RE"; then
  : # branch (b): PRODUCT-DECISION / convergence shorthand → scan
elif printf '%s' "$QTEXT" | grep -qE "$FINDING_ID_RE" \
  && printf '%s' "$QTEXT" | grep -qiE "$FINDING_CTX_RE"; then
  : # branch (b): finding-ID token (case-sensitive F/M) + finding-gate co-text → scan
else
  exit 0  # neither trigger → unscanned
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
Gate render missing: this gate question needs a rendered chat block the user can see, but no visible assistant message exists in the current turn — the user would be answering blind.
This is an automated plugin guard (gate-render), NOT a user denial. Do not stop, and do not treat the question as answered.
Recovery: (1) write the full gate render as an ordinary chat message — the digest, evidence, and visuals the question refers to; (2) then call AskUserQuestion again with the same options.
Project bypass: add "gate-render" to allow_patterns in .geniro/safety.json.
EOF
exit 2
