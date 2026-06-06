#!/usr/bin/env bash
# enforce-state-helper.sh
# PreToolUse hook for Write and Edit — nudges skills toward atomic-state-write.
#
# Scope: writes to canonical state paths under .geniro/ should go through the
# atomic-state-write helper (lib/atomic-state-write.sh), not direct
# Edit/Write calls. The helper guarantees tmp + fsync + rename + fsync-dir
# atomicity. Direct calls truncate-and-rewrite — a reader during the window
# sees a partial file.
#
# Modes:
#   warn   — print to stderr, allow the call (current default)
#   block  — print to stderr, exit 2 (after all skills migrate)
#
# Per-project bypass:
#   .geniro/safety.json — { "allow_patterns": ["enforce-state-helper"] }
#
# Pattern ID: enforce-state-helper
#
# Design rationale: ARCHITECTURE.md §State Files

set -euo pipefail

# Flip this to "block" once all skills migrate to atomic_state_write
# (see ARCHITECTURE.md §State Files).
MODE="warn"

# Consume stdin — REQUIRED first step for Claude Code hooks.
INPUT=$(cat)

# Extract file path from tool input JSON.
FILE_PATH=$(printf '%s' "$INPUT" | jq -r '.tool_input.file_path // ""' 2>/dev/null || echo "")

if [ -z "$FILE_PATH" ]; then
  exit 0
fi

# Locate nearest .geniro/safety.json walking up from cwd.
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
  *" enforce-state-helper "*) exit 0 ;;
esac

# Check if the path is a canonical state-file path (ARCHITECTURE.md §State Files).
# The (^|/) prefix in the patterns below matches both relative (.geniro/...) and
# absolute (/x/.geniro/...) forms.
matches_state_path() {
  local p="$1"
  # Exclusions — files under .geniro/ that are NOT frontmatter-bearing state
  # files and shouldn't trigger the helper warning:
  #   *.lock      — coordination locks (e.g., .geniro/planning/.codebase-map.lock)
  #   .fingerprint.json — pure JSON, no frontmatter
  #   *.tmp / *.tmp.PID.HOST — atomic-write temp files (helper's own intermediate
  #                            file before mv), generic .tmp suffix
  #   *.swp       — vim swap files
  #   *~          — emacs backup files
  #   T1 ephemeral subagent outputs — deterministically transient prose
  #   reports / screenshots, no frontmatter, deleted at Phase Ship:
  #     .kr-out.md, .ce-out.md, .tr-out.md, .adversarial-out.md, .research-out.md
  #     .research-<facet>.md (per-facet research outputs from /plan Phase 1)
  #     notes.md (ad-hoc scratch under <task-dir>/)
  #     playwright-verify.png (pre-Ship visual verification screenshot)
  if echo "$p" | grep -qE '\.lock$|/\.fingerprint\.json$|\.tmp(\.[^/]+)?$|\.swp$|~$|/\.(kr|ce|tr|adversarial|research)-out\.md$|/\.research-[^/]+\.md$|/notes\.md$|/playwright-verify\.png$'; then
    return 1
  fi
  # T1, T2, T3 directories under .geniro/.
  if echo "$p" | grep -qE '(^|/)\.geniro/(state|planning|knowledge|instructions|actions|workflow)/'; then
    return 0
  fi
  # Plugin metadata file (T3 CRUD).
  if echo "$p" | grep -qE '(^|/)\.geniro/\.geniro-state\.json$'; then
    return 0
  fi
  return 1
}

if ! matches_state_path "$FILE_PATH"; then
  exit 0
fi

# Match the right helper to the tier.
suggested_helper() {
  local p="$1"
  if echo "$p" | grep -qE '\.geniro/knowledge/.*\.jsonl$'; then
    echo "atomic_state_append"
  else
    echo "atomic_state_write"
  fi
}

HELPER=$(suggested_helper "$FILE_PATH")

MSG_PREFIX="State-helper [enforce-state-helper]"
MSG_BODY="Direct Edit/Write to canonical state path: $FILE_PATH
$MSG_PREFIX:   Use \`$HELPER\` via Bash for atomicity guarantee.
$MSG_PREFIX:   Pattern:
$MSG_PREFIX:     source \"\${CLAUDE_PLUGIN_ROOT}/lib/atomic-state-write.sh\"
$MSG_PREFIX:     $HELPER \"$FILE_PATH\" <<'EOF'
$MSG_PREFIX:     ...content...
$MSG_PREFIX:     EOF
$MSG_PREFIX:   Spec: skills/_shared/atomic-state-write.md"

if [ "$MODE" = "block" ]; then
  echo "$MSG_PREFIX: $MSG_BODY" >&2
  echo "$MSG_PREFIX: To bypass per-project, add \"enforce-state-helper\" to allow_patterns in .geniro/safety.json." >&2
  exit 2
fi

# warn mode — surface the message, allow the call.
echo "$MSG_PREFIX (warn): $MSG_BODY" >&2
echo "$MSG_PREFIX (warn): This warning becomes a hard block once all Geniro skills finish migrating to the helper." >&2
exit 0
