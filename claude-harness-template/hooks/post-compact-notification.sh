#!/bin/bash
# post-compact-notification.sh
# PostCompact hook - notifies when compaction occurs and suggests re-reading critical files
# Reads trigger and compact_summary from stdin

set -euo pipefail

# Consume stdin - REQUIRED first step
INPUT=$(cat)

# Extract compaction details
TRIGGER=$(echo "$INPUT" | jq -r '.trigger // "manual"' 2>/dev/null || echo "manual")
COMPACT_SUMMARY=$(echo "$INPUT" | jq -r '.compact_summary // ""' 2>/dev/null || echo "")

# Check for active pipeline state
PIPELINE_RESUME=""
TASK_DIR=""
for state_file in "$CLAUDE_PROJECT_DIR"/.claude/.artifacts/planning/*/state.md; do
  if [ -f "$state_file" ]; then
    TASK_DIR=$(dirname "$state_file")
    PIPELINE_RESUME="Active pipeline detected. Read $state_file to resume from the correct phase. Then re-read the current skill file to restore phase instructions."
    break
  fi
done

# Build notification with suggestions
NOTIFICATION=$(jq -n \
  --arg trigger "$TRIGGER" \
  --arg summary "$COMPACT_SUMMARY" \
  --arg pipeline_resume "$PIPELINE_RESUME" \
  --arg task_dir "$TASK_DIR" \
  '{
    "additionalContext": {
      "warning": "Context was compressed by compaction. SKILL.md instructions were lost — you MUST re-read the skill file before continuing.",
      "trigger": $trigger,
      "resume_instructions": [
        "1. Read the current skill SKILL.md to restore phase instructions",
        "2. Read state.md from the active task directory to find your current phase",
        "3. Read spec.md and plan file for task context",
        "4. Continue from the next incomplete phase"
      ],
      "pipeline_resume": $pipeline_resume,
      "task_dir": $task_dir,
      "suggested_files": [
        "CLAUDE.md",
        ".claude/.artifacts/state/pre-compact-snapshot.json"
      ],
      "note": "Compaction lost SKILL.md instructions and conversation nuance. Re-read files before proceeding."
    }
  }')

echo "$NOTIFICATION"

exit 0
