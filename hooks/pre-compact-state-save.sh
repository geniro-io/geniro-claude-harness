#!/bin/bash
# pre-compact-state-save.sh
# PreCompact hook - saves current state before compaction
# Preserves working state, file changes, and timestamp

set -euo pipefail

# Consume stdin - REQUIRED first step
INPUT=$(cat)

# Create .claude directory structure if needed
STATE_DIR="./.geniro/state"
mkdir -p "$STATE_DIR" 2>/dev/null || true

# Get current state information
TIMESTAMP=$(date -u +%Y-%m-%dT%H:%M:%SZ)
WORKING_DIR=$(pwd)

# Get list of changed files (if git repo exists)
CHANGED_FILES=""
if [ -d .git ]; then
  CHANGED_FILES=$(git diff --name-only 2>/dev/null | head -20 || echo "")
fi

# Get current git status summary
GIT_STATUS=""
if [ -d .git ]; then
  GIT_STATUS=$(git status --short 2>/dev/null | head -10 || echo "")
fi

# Check for active pipeline state (implement skill checkpoints)
PIPELINE_STATE=""
TASK_DIR=""
for state_file in .geniro/planning/*/state.md; do
  if [ -f "$state_file" ]; then
    TASK_DIR=$(dirname "$state_file")
    PIPELINE_STATE=$(cat "$state_file" 2>/dev/null | head -10 || echo "")
    break
  fi
done

# Build snapshot JSON
SNAPSHOT=$(jq -n \
  --arg timestamp "$TIMESTAMP" \
  --arg working_dir "$WORKING_DIR" \
  --arg changed_files "$CHANGED_FILES" \
  --arg git_status "$GIT_STATUS" \
  --arg pipeline_state "$PIPELINE_STATE" \
  --arg task_dir "$TASK_DIR" \
  '{
    "pre_compact_snapshot": {
      "timestamp": $timestamp,
      "working_directory": $working_dir,
      "changed_files": ($changed_files | split("\n") | map(select(length > 0))),
      "git_status": ($git_status | split("\n") | map(select(length > 0))),
      "pipeline_state": $pipeline_state,
      "task_dir": $task_dir,
      "hook_trigger": "pre-compact"
    }
  }')

# Save snapshot
SNAPSHOT_FILE="$STATE_DIR/pre-compact-snapshot.json"
echo "$SNAPSHOT" > "$SNAPSHOT_FILE"

# Output informational message
jq -n '{
  "additionalContext": {
    "info": "Pre-compaction state saved",
    "snapshot_location": "'$SNAPSHOT_FILE'",
    "timestamp": "'$TIMESTAMP'"
  }
}' 2>/dev/null || true

exit 0
