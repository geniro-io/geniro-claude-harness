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
FEATURE_ID=""
SPEC_FILE=""
FEATURE_ANCHOR=""
# Pick most-recently-modified state.md (handles concurrent pipelines via worktrees / parallel sessions)
state_file=$(ls -t ./.geniro/planning/*/state.md 2>/dev/null | head -1 || true)
if [ -n "$state_file" ] && [ -f "$state_file" ]; then
  TASK_DIR=$(dirname "$state_file")
  FEATURE_ID=$(grep -m1 '^Feature:' "$state_file" 2>/dev/null | sed 's/^Feature:[[:space:]]*//' || echo "")
  SPEC_FILE=$(grep -m1 '^Spec-file:' "$state_file" 2>/dev/null | sed 's/^Spec-file:[[:space:]]*//' || echo "")
  PIPELINE_RESUME="Active pipeline detected. Read $state_file to resume from the correct phase. Then re-read the current skill file to restore phase instructions."
  if [ -n "$FEATURE_ID" ] && [ "$FEATURE_ID" != "none" ]; then
    FEATURE_ANCHOR="Active feature: $FEATURE_ID. Finalization gate: before ending the pipeline, you MUST run '/geniro:features complete $FEATURE_ID' to move the FEATURES.md row to done."
  fi
fi

# Build notification with suggestions
NOTIFICATION=$(jq -n \
  --arg trigger "$TRIGGER" \
  --arg summary "$COMPACT_SUMMARY" \
  --arg pipeline_resume "$PIPELINE_RESUME" \
  --arg task_dir "$TASK_DIR" \
  --arg feature_id "$FEATURE_ID" \
  --arg spec_file "$SPEC_FILE" \
  --arg feature_anchor "$FEATURE_ANCHOR" \
  '{
    "additionalContext": {
      "warning": "Context was compressed by compaction. SKILL.md instructions were lost — you MUST re-read the skill file before continuing.",
      "trigger": $trigger,
      "resume_instructions": [
        "1. Read the current skill SKILL.md to restore phase instructions",
        "2. Read state.md from the active task directory to find your current phase",
        "3. Read spec.md and plan file for task context",
        "4. If a feature ID is set, re-read the FEATURES.md row and the linked spec file",
        "5. Continue from the next incomplete phase"
      ],
      "pipeline_resume": $pipeline_resume,
      "task_dir": $task_dir,
      "feature_id": $feature_id,
      "spec_file": $spec_file,
      "feature_anchor": $feature_anchor,
      "suggested_files": (
        ["CLAUDE.md", ".geniro/state/pre-compact-snapshot.json", ".geniro/planning/FEATURES.md"]
        + (if $spec_file != "" and $spec_file != "none" then [$spec_file] else [] end)
      ),
      "note": "Compaction lost SKILL.md instructions and conversation nuance. Re-read files before proceeding."
    }
  }')

echo "$NOTIFICATION"

exit 0
