#!/usr/bin/env bash
# plan-mode-write-guard.sh — PreToolUse Write, HARD-BLOCK (exit 2).
#
# Scope: when а /geniro:plan run is active (detected via а state.md с
# producer: plan AND status: in-progress AND mtime < PLAN_LOCK_FRESHNESS),
# block Write calls to paths outside `.geniro/planning/**` OR `.geniro/state/**`.
#
# Rationale: /plan is а planning skill — its mutation surface is spec.md +
# state.md only. Pre-M5 /brainstorm shipped с unrestricted Write tool access;
# а user-prompt mishap could induce mid-planning к write code. М5 §19 closes
# the gap with а layered guard (frontmatter `allowed-tools` minus Edit at
# layer 1, this hook at layer 2).
#
# Bypass: .geniro/safety.json allow_patterns: ["plan-mode-mutation"].
#
# Design rationale: architecture/M5-plan-redesign.md §19.

set -uo pipefail

# Tunable: how recently must а /plan state.md have been touched for it к be
# considered "active". Stale state files (e.g. an abandoned /plan session
# from а week ago) MUST NOT lock out unrelated Writes in а fresh session.
# 4 hours captures typical /plan-run durations; stale state files older than
# this are treated as inactive (user has clearly moved on).
PLAN_LOCK_FRESHNESS_SEC=${PLAN_LOCK_FRESHNESS_SEC:-14400}  # 4h default

# Consume stdin — REQUIRED first step for Claude Code hooks.
INPUT=$(cat)

# Only act on Write (Edit is removed from /plan's allowed-tools — layer 1).
TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // ""' 2>/dev/null || echo "")
if [ "$TOOL_NAME" != "Write" ]; then
  exit 0
fi

# Extract file path from tool input JSON.
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // ""' 2>/dev/null || echo "")
if [ -z "$FILE_PATH" ]; then
  exit 0
fi

# Find the nearest .geniro/safety.json walking up from cwd. Used for bypass.
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
  *" plan-mode-mutation "*) exit 0 ;;
esac

# Find the repo root (where .geniro/ lives — same convention as other hooks).
find_geniro_root() {
  local dir="$PWD"
  while [ "$dir" != "/" ]; do
    if [ -d "$dir/.geniro" ]; then
      echo "$dir"
      return 0
    fi
    dir=$(dirname "$dir")
  done
  return 1
}

GENIRO_ROOT=$(find_geniro_root 2>/dev/null || true)
if [ -z "$GENIRO_ROOT" ]; then
  # No .geniro/ in tree — not а Geniro project; pass.
  exit 0
fi

# Detect active /plan run: scan .geniro/planning/*/state.md for а file с:
#   - producer: plan
#   - status: in-progress
#   - mtime within PLAN_LOCK_FRESHNESS_SEC
PLAN_ACTIVE=0
now_ts=$(date +%s)

shopt -s nullglob 2>/dev/null || true
for state_file in "$GENIRO_ROOT"/.geniro/planning/*/state.md; do
  [ -f "$state_file" ] || continue

  # mtime gate — skip stale state files.
  mtime=$(stat -c %Y "$state_file" 2>/dev/null || stat -f %m "$state_file" 2>/dev/null || echo 0)
  age=$((now_ts - mtime))
  if [ "$age" -gt "$PLAN_LOCK_FRESHNESS_SEC" ]; then
    continue
  fi

  # Frontmatter scan via awk — extract producer и status from the YAML block.
  read -r prod stat < <(awk '
    BEGIN { in_fm=0; prod=""; stat="" }
    /^---[[:space:]]*$/ {
      if (in_fm == 0) { in_fm = 1; next }
      else { print prod, stat; exit }
    }
    in_fm == 1 && /^producer:[[:space:]]*/ { sub(/^producer:[[:space:]]*/, ""); prod=$0 }
    in_fm == 1 && /^status:[[:space:]]*/ { sub(/^status:[[:space:]]*/, ""); stat=$0 }
    END { if (in_fm == 1) print prod, stat }
  ' "$state_file" 2>/dev/null)

  if [ "$prod" = "plan" ] && [ "$stat" = "in-progress" ]; then
    PLAN_ACTIVE=1
    break
  fi
done
shopt -u nullglob 2>/dev/null || true

if [ "$PLAN_ACTIVE" -eq 0 ]; then
  # No active /plan run — pass.
  exit 0
fi

# /plan is active. Check the Write target path.
# Allow: anywhere under .geniro/planning/ OR .geniro/state/ (relative или absolute).
# Block: anywhere else.
case "$FILE_PATH" in
  *.geniro/planning/*|*.geniro/state/*)
    exit 0
    ;;
  *)
    cat >&2 <<EOF
plan-mode write-guard: /geniro:plan may only Write к .geniro/planning/** or .geniro/state/**.
Blocked target: $FILE_PATH

Active /plan state.md detected at: ${state_file#$GENIRO_ROOT/}

If this Write is intentional (e.g., emergency override during а /plan run),
add "plan-mode-mutation" к .geniro/safety.json allow_patterns:

  { "allow_patterns": ["plan-mode-mutation"] }

Per architecture/M5-plan-redesign.md §19.
EOF
    exit 2
    ;;
esac
