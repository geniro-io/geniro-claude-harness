#!/bin/bash
# context-statusline.sh
# StatusLine hook - receives context metrics from Claude Code and writes bridge file
# Bridge file is read by context-monitor.sh to trigger low-context alerts

set -euo pipefail

# Consume stdin - REQUIRED first step
INPUT=$(cat)

# Clean up stale bridge files older than 24h
find /tmp/claude-ctx-*.json -mtime +1 -delete 2>/dev/null || true

# Extract fields using jq, with grep/sed fallback
if command -v jq &>/dev/null; then
  SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // empty')
  REMAINING=$(echo "$INPUT" | jq -r '.context_window.remaining_percentage // empty')
  USED=$(echo "$INPUT" | jq -r '.context_window.used_percentage // empty')
  WIN_SIZE=$(echo "$INPUT" | jq -r '.context_window.context_window_size // empty')
  MODEL_ID=$(echo "$INPUT" | jq -r '.model.id // empty')
else
  # Fallback: basic extraction with grep/sed
  SESSION_ID=$(echo "$INPUT" | grep -o '"session_id"[[:space:]]*:[[:space:]]*"[^"]*"' | sed 's/.*: *"//;s/"//')
  REMAINING=$(echo "$INPUT" | grep -o '"remaining_percentage"[[:space:]]*:[[:space:]]*[0-9]*' | sed 's/.*: *//')
  USED=$(echo "$INPUT" | grep -o '"used_percentage"[[:space:]]*:[[:space:]]*[0-9]*' | sed 's/.*: *//')
  WIN_SIZE=$(echo "$INPUT" | grep -o '"context_window_size"[[:space:]]*:[[:space:]]*[0-9]*' | sed 's/.*: *//')
  MODEL_ID=$(echo "$INPUT" | grep -o '"id"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed 's/.*: *"//;s/"//')
fi

# Bail if we don't have the minimum required data
if [ -z "$SESSION_ID" ] || [ -z "$REMAINING" ]; then exit 0; fi

BRIDGE_FILE="/tmp/claude-ctx-${SESSION_ID}.json"
TIMESTAMP=$(date +%s)

# Write bridge file atomically (write to temp, then move)
TMPFILE=$(mktemp /tmp/claude-ctx-XXXXXX)
if command -v jq &>/dev/null; then
  jq -n \
    --arg sid "$SESSION_ID" \
    --argjson rem "${REMAINING:-0}" \
    --argjson used "${USED:-0}" \
    --argjson win "${WIN_SIZE:-0}" \
    --arg model "${MODEL_ID:-unknown}" \
    --argjson ts "$TIMESTAMP" \
    '{
      session_id: $sid,
      context_remaining_percent: $rem,
      context_used_percent: $used,
      context_window_size: $win,
      model_id: $model,
      timestamp: $ts
    }' > "$TMPFILE"
else
  cat > "$TMPFILE" <<EOF
{"session_id":"${SESSION_ID}","context_remaining_percent":${REMAINING:-0},"context_used_percent":${USED:-0},"context_window_size":${WIN_SIZE:-0},"model_id":"${MODEL_ID:-unknown}","timestamp":${TIMESTAMP}}
EOF
fi

mv "$TMPFILE" "$BRIDGE_FILE"

exit 0
