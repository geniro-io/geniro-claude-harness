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
# Pick the active pipeline state.md using a three-tier branch-aware strategy:
#   1. Direct directory match — tries .geniro/planning/<slug>/state.md (slug form) AND
#      .geniro/planning/<branch>/state.md (original branch name). The branch-name lookup handles
#      task-dirs with a '/' in the branch name (e.g. feat/ci-22-foo → planning/feat/ci-22-foo/).
#   2. Branch:-field grep — recursively search all state.md files for a 'Branch:' line matching
#      the current branch (mtime tiebreak among multiple matches). Handles arbitrary task-dir depth.
#   3. Mtime fallback — most-recently-modified state.md found via recursive find (preserves
#      behavior for older pipelines written before the Branch: field existed).
state_file=""
branch="$(git branch --show-current 2>/dev/null || true)"
if [ -z "${branch:-}" ]; then
  branch="detached-$(git rev-parse --short HEAD 2>/dev/null || echo unknown)"
fi
slug="$(printf '%s' "$branch" | tr '[:upper:]' '[:lower:]' | sed -E 's#[^a-z0-9]+#-#g; s#^-+##; s#-+$##' || true)"
slug="${slug:0:60}"
slug="${slug%-}"

# Tier 1: direct directory match — try slug form first, then original branch name (handles feat/foo)
if [ -n "${slug:-}" ] && [ -f "./.geniro/planning/$slug/state.md" ]; then
  state_file="./.geniro/planning/$slug/state.md"
elif [ -n "${branch:-}" ] && [ -f "./.geniro/planning/$branch/state.md" ]; then
  state_file="./.geniro/planning/$branch/state.md"
fi

# Tier 2: grep Branch: field across all state.md files (mtime-ordered for tiebreak)
# Uses recursive find so task-dirs with '/' in branch names (e.g. feat/ci-22-foo) are included.
_state_candidates() {
  find ./.geniro/planning -name 'state.md' -type f 2>/dev/null | while IFS= read -r p; do
    mtime=$(stat -f '%m' "$p" 2>/dev/null || stat -c '%Y' "$p" 2>/dev/null || true)
    [ -n "$mtime" ] && printf '%s %s\n' "$mtime" "$p"
  done | sort -rn | cut -d' ' -f2-
}
if [ -z "$state_file" ] && [ -n "${branch:-}" ]; then
  while IFS= read -r candidate; do
    [ -z "$candidate" ] && continue
    branch_field=$(grep -m1 '^Branch:' "$candidate" 2>/dev/null | sed 's/^Branch:[[:space:]]*//' || true)
    if [ -n "$branch_field" ] && [ "$branch_field" = "$branch" ]; then
      state_file="$candidate"
      break
    fi
  done <<EOF
$(_state_candidates)
EOF
fi

# Tier 3: mtime fallback (legacy pipelines without Branch: field)
if [ -z "$state_file" ]; then
  state_file=$(_state_candidates | head -1 || true)
fi
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
        ["CLAUDE.md", ".geniro/planning/FEATURES.md"]
        + (if $spec_file != "" and $spec_file != "none" then [$spec_file] else [] end)
      ),
      "note": "Compaction lost SKILL.md instructions and conversation nuance. Re-read files before proceeding."
    }
  }')

echo "$NOTIFICATION"

exit 0
