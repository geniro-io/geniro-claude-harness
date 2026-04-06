#!/bin/bash
# context-monitor.sh
# PostToolUse hook for all tools — monitors remaining context and alerts when low
#
# Data sources (in priority order):
#   1. Bridge file written by StatusLine: /tmp/claude-ctx-{session_id}.json
#   2. JSONL transcript fallback: parses usage from transcript_path in stdin
#
# Adaptive thresholds:
#   200K context (default): warning=35%, critical=25%, emergency=15%
#   1M context:             warning=80%, critical=70%, emergency=60%
#
# Debounce: WARNING fires every 5 tool calls; CRITICAL/EMERGENCY always fire.

set -euo pipefail

# --- Consume stdin (REQUIRED first step for PostToolUse hooks) ---
INPUT=$(cat)

# --- Artifacts & debounce setup ---
ARTIFACTS_DIR="${CLAUDE_PROJECT_DIR:-.}/.claude/.artifacts/context-monitor"
mkdir -p "$ARTIFACTS_DIR" 2>/dev/null || ARTIFACTS_DIR="/tmp"
DEBOUNCE_FILE="$ARTIFACTS_DIR/claude-context-monitor.debounce"
DEBOUNCE_INTERVAL=5

if [ -f "$DEBOUNCE_FILE" ]; then
  DEBOUNCE_COUNT=$(cat "$DEBOUNCE_FILE" 2>/dev/null || echo "0")
else
  DEBOUNCE_COUNT=0
fi
DEBOUNCE_COUNT=$((DEBOUNCE_COUNT + 1))

# --- Extract session_id and transcript_path from stdin ---
SESSION_ID=""
TRANSCRIPT_PATH=""
if command -v jq &>/dev/null; then
  SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // empty' 2>/dev/null || true)
  TRANSCRIPT_PATH=$(echo "$INPUT" | jq -r '.transcript_path // empty' 2>/dev/null || true)
else
  SESSION_ID=$(echo "$INPUT" | grep -o '"session_id"[[:space:]]*:[[:space:]]*"[^"]*"' | sed 's/.*: *"//;s/"//' || true)
  TRANSCRIPT_PATH=$(echo "$INPUT" | grep -o '"transcript_path"[[:space:]]*:[[:space:]]*"[^"]*"' | sed 's/.*: *"//;s/"//' || true)
fi

# --- Source 1: Bridge file (primary) ---
CONTEXT_PCT=""
CONTEXT_WINDOW_SIZE=""
BRIDGE_FILE=""

if [ -n "$SESSION_ID" ]; then
  BRIDGE_FILE="/tmp/claude-ctx-${SESSION_ID}.json"
fi

if [ -n "$BRIDGE_FILE" ] && [ -f "$BRIDGE_FILE" ]; then
  # Check staleness: skip if older than 5 minutes (300 seconds)
  BRIDGE_STALE=0
  if [[ "$OSTYPE" == darwin* ]]; then
    BRIDGE_MTIME=$(stat -f %m "$BRIDGE_FILE" 2>/dev/null || echo "0")
  else
    BRIDGE_MTIME=$(stat -c %Y "$BRIDGE_FILE" 2>/dev/null || echo "0")
  fi
  NOW=$(date +%s)
  if [ $((NOW - BRIDGE_MTIME)) -gt 300 ]; then
    BRIDGE_STALE=1
  fi

  if [ "$BRIDGE_STALE" -eq 0 ]; then
    CONTEXT_PCT=$(jq -r '.context_remaining_percent // empty' "$BRIDGE_FILE" 2>/dev/null || true)
    CONTEXT_WINDOW_SIZE=$(jq -r '.context_window_size // empty' "$BRIDGE_FILE" 2>/dev/null || true)
  fi
fi

# --- Source 2: JSONL transcript fallback ---
if [ -z "$CONTEXT_PCT" ] && [ -n "$TRANSCRIPT_PATH" ] && [ -f "$TRANSCRIPT_PATH" ]; then
  # Extract the latest usage line from the transcript
  USAGE_LINE=$(tail -100 "$TRANSCRIPT_PATH" 2>/dev/null | grep '"usage"' | tail -1 || true)

  if [ -n "$USAGE_LINE" ]; then
    # Sum input_tokens + cache_read_input_tokens + cache_creation_input_tokens
    TOKENS_USED=$(echo "$USAGE_LINE" | jq '
      (.usage.input_tokens // 0)
      + (.usage.cache_read_input_tokens // 0)
      + (.usage.cache_creation_input_tokens // 0)
    ' 2>/dev/null || true)

    if [ -n "$TOKENS_USED" ] && [ "$TOKENS_USED" != "null" ] && [ "$TOKENS_USED" -gt 0 ] 2>/dev/null; then
      # Default to 200K when we don't know the window size from JSONL
      FALLBACK_WINDOW=200000
      # remaining % = (window - used) * 100 / window  (integer math)
      if [ "$TOKENS_USED" -lt "$FALLBACK_WINDOW" ]; then
        CONTEXT_PCT=$(( (FALLBACK_WINDOW - TOKENS_USED) * 100 / FALLBACK_WINDOW ))
      else
        CONTEXT_PCT=0
      fi
      # Leave CONTEXT_WINDOW_SIZE empty — we don't know it from JSONL
    fi
  fi
fi

# --- Graceful degradation: no context data available, exit silently ---
if [ -z "$CONTEXT_PCT" ]; then
  echo "$DEBOUNCE_COUNT" > "$DEBOUNCE_FILE"
  exit 0
fi

# --- Determine adaptive thresholds based on context_window_size ---
# Default: 200K thresholds
THRESH_WARNING=35
THRESH_CRITICAL=25
THRESH_EMERGENCY=15
THRESHOLD_LABEL="200K model"

if [ -n "$CONTEXT_WINDOW_SIZE" ]; then
  # Treat anything >= 500K as a large-context model (1M class)
  if [ "$CONTEXT_WINDOW_SIZE" -ge 500000 ] 2>/dev/null; then
    THRESH_WARNING=80
    THRESH_CRITICAL=70
    THRESH_EMERGENCY=60
    THRESHOLD_LABEL="1M model"
  fi
fi

# --- Determine alert level (integer comparison only — no bc dependency) ---
# Strip any decimal portion for safe integer comparison
CONTEXT_PCT_INT="${CONTEXT_PCT%%.*}"

ALERT_LEVEL=""
THRESHOLD_DESC=""

if [ "$CONTEXT_PCT_INT" -le "$THRESH_EMERGENCY" ] 2>/dev/null; then
  ALERT_LEVEL="emergency"
  THRESHOLD_DESC="≤${THRESH_EMERGENCY}% (${THRESHOLD_LABEL})"
elif [ "$CONTEXT_PCT_INT" -le "$THRESH_CRITICAL" ] 2>/dev/null; then
  ALERT_LEVEL="critical"
  THRESHOLD_DESC="≤${THRESH_CRITICAL}% (${THRESHOLD_LABEL})"
elif [ "$CONTEXT_PCT_INT" -le "$THRESH_WARNING" ] 2>/dev/null; then
  ALERT_LEVEL="warning"
  THRESHOLD_DESC="≤${THRESH_WARNING}% (${THRESHOLD_LABEL})"
fi

# --- Emergency: auto-write handoff note ---
if [ "$ALERT_LEVEL" = "emergency" ]; then
  HANDOFF_FILE="$ARTIFACTS_DIR/claude-emergency-handoff.md"
  cat > "$HANDOFF_FILE" <<EOF
# EMERGENCY CONTEXT HANDOFF
Context at critical level: ${CONTEXT_PCT}%
Timestamp: $(date -u +%Y-%m-%dT%H:%M:%SZ)

## State to preserve:
- Current working directory: $(pwd)
- Recent files changed: $(git diff --name-only 2>/dev/null | head -10 || echo "N/A")

## Recommended actions:
1. Save current progress
2. Document current task state in CLAUDE.md
3. Consider starting fresh session if task is complex
EOF
fi

# --- Emit output based on level and debounce ---
# CRITICAL and EMERGENCY always fire; WARNING only on debounce interval
SHOULD_EMIT=0

if [ "$ALERT_LEVEL" = "critical" ] || [ "$ALERT_LEVEL" = "emergency" ]; then
  SHOULD_EMIT=1
elif [ "$ALERT_LEVEL" = "warning" ] && [ $((DEBOUNCE_COUNT % DEBOUNCE_INTERVAL)) -eq 0 ]; then
  SHOULD_EMIT=1
fi

if [ "$SHOULD_EMIT" -eq 1 ] && [ -n "$ALERT_LEVEL" ]; then
  # Build recommendation based on level
  RECOMMENDATION="Consider /compact or spawning sub-agents"
  if [ "$ALERT_LEVEL" = "emergency" ]; then
    RECOMMENDATION="STOP complex work. Run /compact NOW, write handoff notes, or start a new session"
  elif [ "$ALERT_LEVEL" = "critical" ]; then
    RECOMMENDATION="Run /compact soon. Avoid large file reads. Consider spawning sub-agents for remaining work"
  fi

  if command -v jq &>/dev/null; then
    jq -n \
      --arg level "$ALERT_LEVEL" \
      --arg pct "$CONTEXT_PCT" \
      --arg window "${CONTEXT_WINDOW_SIZE:-unknown}" \
      --arg threshold "$THRESHOLD_DESC" \
      --arg recommendation "$RECOMMENDATION" \
      '{
        "additionalContext": {
          "warning": "Context usage alert",
          "level": $level,
          "context_remaining_percent": $pct,
          "context_window_size": $window,
          "threshold": $threshold,
          "recommendation": $recommendation
        }
      }' 2>/dev/null || true
  else
    cat <<EOJSON
{"additionalContext":{"warning":"Context usage alert","level":"${ALERT_LEVEL}","context_remaining_percent":"${CONTEXT_PCT}","context_window_size":"${CONTEXT_WINDOW_SIZE:-unknown}","threshold":"${THRESHOLD_DESC}","recommendation":"${RECOMMENDATION}"}}
EOJSON
  fi
fi

# --- Update debounce counter ---
echo "$DEBOUNCE_COUNT" > "$DEBOUNCE_FILE"

exit 0
