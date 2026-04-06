#!/bin/bash
# context-monitor.sh
# PostToolUse hook for all tools - monitors remaining context and alerts when low
# Debounced: warns once every 5 tool calls

set -euo pipefail

# Consume stdin - REQUIRED first step
INPUT=$(cat)

# Debounce check: track tool calls and warn every 5 calls
# Use .claude/.artifacts/ for persistence (git-ignored), fall back to /tmp/
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

# Check for context bridge file that may contain context metrics
CONTEXT_BRIDGE="/tmp/claude-ctx-*.json"
CONTEXT_PCT=""

# Try to find and read context bridge file
for bridge_file in /tmp/claude-ctx-*.json; do
  if [ -f "$bridge_file" ]; then
    CONTEXT_PCT=$(jq -r '.context_remaining_percent // empty' "$bridge_file" 2>/dev/null || echo "")
    if [ -n "$CONTEXT_PCT" ]; then
      break
    fi
  fi
done

# Graceful degradation: if no context data available, exit silently
if [ -z "$CONTEXT_PCT" ]; then
  echo "$DEBOUNCE_COUNT" > "$DEBOUNCE_FILE"
  exit 0
fi

# Only output warning on debounce interval (every 5 calls)
if [ $((DEBOUNCE_COUNT % DEBOUNCE_INTERVAL)) -eq 0 ]; then
  ALERT_LEVEL=""

  # Check context thresholds (requires bc for float comparison; skip if unavailable)
  if ! command -v bc &>/dev/null; then
    echo "$DEBOUNCE_COUNT" > "$DEBOUNCE_FILE"
    exit 0
  fi
  if (( $(echo "$CONTEXT_PCT <= 15" | bc -l) )); then
    ALERT_LEVEL="emergency"
    # Auto-write handoff note on emergency
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
  elif (( $(echo "$CONTEXT_PCT <= 25" | bc -l) )); then
    ALERT_LEVEL="critical"
  elif (( $(echo "$CONTEXT_PCT <= 35" | bc -l) )); then
    ALERT_LEVEL="warning"
  fi

  if [ -n "$ALERT_LEVEL" ]; then
    jq -n \
      --arg level "$ALERT_LEVEL" \
      --arg pct "$CONTEXT_PCT" \
      '{
        "additionalContext": {
          "warning": "Context usage alert",
          "level": $level,
          "context_remaining_percent": $pct,
          "threshold": ($level |
            if . == "emergency" then "≤15%"
            elif . == "critical" then "≤25%"
            elif . == "warning" then "≤35%"
            else "unknown" end)
        }
      }' 2>/dev/null || true
  fi
fi

# Update debounce counter
echo "$DEBOUNCE_COUNT" > "$DEBOUNCE_FILE"

exit 0
