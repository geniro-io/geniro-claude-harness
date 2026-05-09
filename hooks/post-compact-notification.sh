#!/bin/bash
# post-compact-notification.sh
# SessionStart hook (matcher: "compact") — restores context after compaction by injecting
# additionalContext that names files the model should re-read (custom instructions,
# planning state, active spec). PostCompact event itself does not support additionalContext
# per Anthropic docs — SessionStart with matcher: "compact" is the canonical mechanism.

set -euo pipefail

# Consume stdin - REQUIRED first step
INPUT=$(cat)

# Honor cwd from input — defensive against harnesses that invoke hooks from a different cwd
HOOK_CWD=$(echo "$INPUT" | jq -r '.cwd // empty' 2>/dev/null || echo "")
if [ -n "$HOOK_CWD" ] && [ -d "$HOOK_CWD" ]; then
  cd "$HOOK_CWD" || true
fi

# Extract SessionStart fields. SessionStart provides `source` (one of:
# startup/resume/clear/compact) — not `trigger`. compact_summary is not part of the
# SessionStart input shape; we drop it.
SOURCE=$(echo "$INPUT" | jq -r '.source // "compact"' 2>/dev/null || echo "compact")

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

# Tier 1: direct directory match — try slug form first, then original branch name (handles feat/foo).
# Two layouts are supported per skills/_shared/within-skill-state-handoff.md:
#   - .geniro/planning/<slug>/state.md (per-task pipeline planning dir; implement/decompose/review)
#   - .geniro/state/<skill>/state-<slug>.md OR .geniro/state/debug/HYPOTHESES-<slug>.md
#     (per-skill state dir; follow-up/refactor/debug/improve-template)
# First hit wins. Probe per-task layout first (slug+branch), then per-skill layouts (slug-scoped names).
if [ -n "${slug:-}" ] && [ -f "./.geniro/planning/$slug/state.md" ]; then
  state_file="./.geniro/planning/$slug/state.md"
elif [ -n "${branch:-}" ] && [ -f "./.geniro/planning/$branch/state.md" ]; then
  state_file="./.geniro/planning/$branch/state.md"
fi
if [ -z "$state_file" ] && [ -n "${slug:-}" ]; then
  for _candidate in \
    "./.geniro/state/follow-up/state-${slug}.md" \
    "./.geniro/state/refactor/state-${slug}.md" \
    "./.geniro/state/debug/HYPOTHESES-${slug}.md" \
    "./.geniro/state/improve-template/state-${slug}.md"; do
    if [ -f "$_candidate" ]; then
      state_file="$_candidate"
      break
    fi
  done
fi

# Tier 2: grep Branch: field across all state files (mtime-ordered for tiebreak).
# Uses recursive find so task-dirs with '/' in branch names (e.g. feat/ci-22-foo) are included.
# Combines both layouts: planning/*/state.md AND state/<skill>/{state-*.md,HYPOTHESES-*.md}.
_state_candidates() {
  {
    find ./.geniro/planning -name 'state.md' -type f 2>/dev/null
    find ./.geniro/state -name 'state-*.md' -type f 2>/dev/null
    find ./.geniro/state -name 'HYPOTHESES-*.md' -type f 2>/dev/null
  } | while IFS= read -r p; do
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
ACTIVE_SKILL=""
if [ -n "$state_file" ] && [ -f "$state_file" ]; then
  TASK_DIR=$(dirname "$state_file")
  FEATURE_ID=$(grep -m1 '^Feature:' "$state_file" 2>/dev/null | sed 's/^Feature:[[:space:]]*//' || echo "")
  SPEC_FILE=$(grep -m1 '^Spec-file:' "$state_file" 2>/dev/null | sed 's/^Spec-file:[[:space:]]*//' || echo "")
  PIPELINE_RESUME="Active pipeline detected. Read $state_file to resume from the correct phase. Then re-read the current skill file to restore phase instructions."
  if [ -n "$FEATURE_ID" ] && [ "$FEATURE_ID" != "none" ]; then
    FEATURE_ANCHOR="Active feature: $FEATURE_ID. Finalization gate: before ending the pipeline, you MUST run '/geniro:features complete $FEATURE_ID' to move the FEATURES.md row to done."
  fi
  # Derive active skill from state-file path. Two layouts are possible:
  #   .geniro/state/<skill>/state-*.md      (per-skill state dir)
  #   .geniro/planning/<task-slug>/state.md (per-task planning dir)
  # For the planning layout the slug is a branch name, not a skill — leave ACTIVE_SKILL
  # empty in that case so we don't suggest a non-existent instructions file.
  case "$state_file" in
    *"/.geniro/state/"*)
      # strip leading "*/.geniro/state/" then take the first path segment
      _tail="${state_file#*/.geniro/state/}"
      ACTIVE_SKILL="${_tail%%/*}"
      ;;
  esac
fi

# Assemble the suggested-files list as a newline-separated bullet list. Always include
# CLAUDE.md, the FEATURES.md backlog, the global instructions, and the cross-cutting
# code-style instructions. Conditionally add the active-skill instructions file and the
# spec file when known.
SUGGESTED_FILES="- CLAUDE.md
- .geniro/planning/FEATURES.md
- .geniro/instructions/global.md
- .geniro/instructions/code-style.md"
if [ -n "$ACTIVE_SKILL" ]; then
  SUGGESTED_FILES="$SUGGESTED_FILES
- .geniro/instructions/$ACTIVE_SKILL.md (if present)"
fi
if [ -n "$SPEC_FILE" ] && [ "$SPEC_FILE" != "none" ]; then
  SUGGESTED_FILES="$SUGGESTED_FILES
- $SPEC_FILE"
fi

# Build the additionalContext string. Numbered resume steps mention the three custom-
# instruction files so the model re-hydrates the user's workflow rules first.
if [ -n "$ACTIVE_SKILL" ]; then
  _skill_step="2. Re-read .geniro/instructions/global.md and .geniro/instructions/$ACTIVE_SKILL.md (if present) — your custom workflow rules"
else
  _skill_step="2. Re-read .geniro/instructions/global.md and .geniro/instructions/<active-skill>.md (if present) — your custom workflow rules"
fi

ADDITIONAL_CONTEXT="Context was compressed by compaction (SessionStart source: $SOURCE). SKILL.md instructions and conversation nuance were lost — re-read these files before continuing:

$SUGGESTED_FILES

Resume steps:
1. Read the current skill SKILL.md to restore phase instructions
$_skill_step
3. Re-read .geniro/instructions/code-style.md (if present) — your project's cross-cutting code-style rules
4. Read state.md from the active task directory to find your current phase
5. Read spec.md and plan file for task context
6. If a feature ID is set, re-read the FEATURES.md row and the linked spec file
7. Continue from the next incomplete phase"

if [ -n "$PIPELINE_RESUME" ]; then
  ADDITIONAL_CONTEXT="$ADDITIONAL_CONTEXT

$PIPELINE_RESUME"
fi
if [ -n "$FEATURE_ANCHOR" ]; then
  ADDITIONAL_CONTEXT="$ADDITIONAL_CONTEXT

$FEATURE_ANCHOR"
fi

# Emit SessionStart-shaped output. Per Anthropic docs, hookSpecificOutput.additionalContext
# is a STRING that is injected into Claude's next-turn context.
NOTIFICATION=$(jq -n \
  --arg additional_context "$ADDITIONAL_CONTEXT" \
  '{
    "hookSpecificOutput": {
      "hookEventName": "SessionStart",
      "additionalContext": $additional_context
    }
  }')

echo "$NOTIFICATION"

exit 0
