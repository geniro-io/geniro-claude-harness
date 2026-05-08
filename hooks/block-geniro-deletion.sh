#!/bin/bash
# block-geniro-deletion.sh
# PreToolUse hook for Bash - prevents bulk deletion of .geniro/ contents.
#
# .geniro/ holds user-authored persistent state: instructions/, actions/,
# workflow/, planning/FEATURES.md, planning/<task>/..., knowledge/learnings.jsonl,
# review-findings-state.md, debug/findings-state.md, .geniro-state.json.
# A single accidental `rm -rf .geniro/` (or equivalent) destroys all of it.
# This hook blocks the patterns that have caused real-world data loss.
#
# Allowed by design (NOT blocked):
#   - rm -f <single-file>          (any depth — required by skills' state cleanup)
#   - rm -rf .geniro/<top>/<sub>/  (3+ path segments — task-dir / slug-scoped trees)
#
# Blocked by default:
#   - rm -rf .geniro / .geniro/                    (whole tree)
#   - rm -rf .geniro/<single-segment>              (e.g. .geniro/instructions/)
#   - find <path-with-.geniro> ... -delete         (bulk find-delete)
#   - git worktree remove                          (worktrees often hold un-routed state)
#
# Per-project allowlist: .geniro/safety.json (in cwd or any ancestor) can opt out
# via "allow_patterns".
#
# Pattern IDs: rm-geniro-tree, rm-geniro-subdir, find-geniro-delete,
#              worktree-remove-with-state, git-add-force-geniro

set -euo pipefail

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // ""' 2>/dev/null || echo "")

if [ -z "$COMMAND" ]; then
  exit 0
fi

# Pad and collapse newlines (mirrors block-dangerous-git.sh) so multi-line
# heredocs and embedded newlines can't slip past whitespace-anchored matchers.
PADDED=" ${COMMAND//$'\n'/ } "

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

is_allowed() {
  local pattern_id="$1"
  case " $ALLOWED " in
    *" $pattern_id "*) return 0 ;;
    *) return 1 ;;
  esac
}

block() {
  local pattern_id="$1"
  local message="$2"
  echo "Geniro safety blocked [$pattern_id]: $message" >&2
  echo "Command: $COMMAND" >&2
  if [ -n "$SAFETY_FILE" ]; then
    echo "To allow this pattern, add \"$pattern_id\" to allow_patterns in $SAFETY_FILE" >&2
  else
    echo "To allow this pattern in this project, create .geniro/safety.json with: {\"allow_patterns\": [\"$pattern_id\"]}" >&2
  fi
  exit 2
}

# Does the command include `rm` with -r (in any flag combination: -rf, -fr, -Rf, -R, --recursive)?
has_rm_recursive() {
  echo "$PADDED" | grep -qE 'rm[[:space:]]+([^|;&]*[[:space:]])?-[a-zA-Z]*r[a-zA-Z]*[[:space:]]' && return 0
  echo "$PADDED" | grep -qE 'rm[[:space:]]+([^|;&]*[[:space:]])?-[a-zA-Z]*R[a-zA-Z]*[[:space:]]' && return 0
  echo "$PADDED" | grep -qE 'rm[[:space:]]+([^|;&]*[[:space:]])?--recursive[[:space:]]' && return 0
  return 1
}

# 1. rm -rf .geniro / .geniro/ (bare — whole tree)
if ! is_allowed "rm-geniro-tree"; then
  if has_rm_recursive; then
    if echo "$PADDED" | grep -qE '(/|[[:space:]"'"'"'])\.geniro/?[[:space:]"'"'"';|&]'; then
      block "rm-geniro-tree" "rm -rf .geniro/ would wipe ALL plugin runtime + user-authored content (instructions, actions, workflow, FEATURES.md, learnings, planning artifacts). Use \`rm -f <single-file>\` for individual deletes, or run /geniro:cleanup for full uninstall."
    fi
  fi
fi

# 2. rm -rf .geniro/<single-segment> (e.g. .geniro/instructions/, .geniro/planning/, .geniro/state/)
#    Allows .geniro/<top>/<sub>/... (3+ segments — task-dirs, slug-scoped trees).
if ! is_allowed "rm-geniro-subdir"; then
  if has_rm_recursive; then
    # Match .geniro/<seg>/? as a complete arg (no second segment after).
    if echo "$PADDED" | grep -qE '(/|[[:space:]"'"'"'])\.geniro/[a-zA-Z0-9_.-]+/?[[:space:]"'"'"';|&]'; then
      # Confirm there is no `.geniro/<seg>/<seg2>` form anywhere — that variant is allowed.
      if ! echo "$PADDED" | grep -qE '(\./)?\.geniro/[a-zA-Z0-9_.-]+/[a-zA-Z0-9_.-]+'; then
        block "rm-geniro-subdir" "rm -rf on a top-level .geniro/ subdirectory wipes that entire category of user content. Allowed: deeper paths like .geniro/planning/<task-dir>/ (3+ segments). Use \`rm -f\` per-file for individual deletes."
      fi
    fi
  fi
fi

# 2b. rm -rf .geniro/state/<single-segment>/ — targets a per-skill state subdir
#     (follow-up, refactor, improve-template, debug). Wiping it destroys the
#     parallel-branches' slug files still in flight on other branches. Slug-scoped
#     single-file deletes are still allowed via 4+ segment paths.
if ! is_allowed "rm-geniro-state-subdir"; then
  if has_rm_recursive; then
    # Match .geniro/state/<seg>/? as a complete arg with no further segment.
    if echo "$PADDED" | grep -qE '(/|[[:space:]"'"'"'])\.geniro/state/[a-zA-Z0-9_.-]+/?[[:space:]"'"'"';|&]'; then
      if ! echo "$PADDED" | grep -qE '(\./)?\.geniro/state/[a-zA-Z0-9_.-]+/[a-zA-Z0-9_.-]+'; then
        # Allow single-file deletes at this depth (filenames have a dot+extension).
        # If the matched segment looks like a filename (e.g. review-findings-state.md,
        # pre-compact-snapshot.json), let it through.
        if echo "$PADDED" | grep -qE '(/|[[:space:]"'"'"'])\.geniro/state/[a-zA-Z0-9_.-]+\.[a-zA-Z0-9]+[[:space:]"'"'"';|&]'; then
          : # 3-segment file delete (e.g. .geniro/state/review-findings-state.md) — allow
        else
          block "rm-geniro-state-subdir" "rm -rf on a .geniro/state/<skill>/ subdirectory wipes parallel-branch slug files still in flight. Allowed: single-file deletes (.geniro/state/<file>.md) and 4+ segment paths (.geniro/state/<skill>/state-<slug>.md). Use \`rm -f <single-file>\` for cleanup."
        fi
      fi
    fi
  fi
fi

# 3. find ... .geniro ... -delete  (any flavor of find-delete that touches .geniro)
if ! is_allowed "find-geniro-delete"; then
  if echo "$PADDED" | grep -qE 'find[[:space:]]+[^|;&]*\.geniro[^|;&]*-delete'; then
    block "find-geniro-delete" "find ... -delete on .geniro/ wipes user-authored content in bulk. Iterate file-by-file (\`rm -f\` per path, or pathlib.Path.unlink in Python) so each deletion is auditable."
  fi
fi

# 4. git worktree remove  (worktrees commonly contain .geniro/ state not routed
#    through ${PRIMARY_ROOT} — removal silently destroys it).
if ! is_allowed "worktree-remove-with-state"; then
  if echo "$PADDED" | grep -qE 'git[[:space:]]+worktree[[:space:]]+remove[[:space:]]'; then
    block "worktree-remove-with-state" "git worktree remove destroys the gitignored .geniro/ in the worktree. Verify the worktree's .geniro/ is empty (or that all needed state was routed to the primary worktree via _shared/primary-worktree.md) before removing."
  fi
fi

# 5. git add -f / --force on .geniro/ paths. Force-adding ignored files makes them
#    appear in the IDE's Source Control panel — and IDE "Discard All Changes" then
#    becomes a one-click data-loss vector (real incident: Cursor SCM discard wiped
#    .geniro/actions/*.md after they were force-added). The correct path for files
#    that should be tracked is to negate them in .gitignore (e.g. !.geniro/actions/),
#    not to bypass the ignore via -f.
if ! is_allowed "git-add-force-geniro"; then
  # `git add` invocation with -f or --force present, AND a .geniro/ path argument.
  if echo "$PADDED" | grep -qE 'git[[:space:]]+add[[:space:]]'; then
    if echo "$PADDED" | grep -qE 'git[[:space:]]+add[[:space:]]+([^|;&]*[[:space:]])?(-[a-zA-Z]*f[a-zA-Z]*[[:space:]]|--force[[:space:]])'; then
      if echo "$PADDED" | grep -qE '(/|[[:space:]"'"'"'])\.geniro(/|[[:space:]"'"'"';|&])'; then
        block "git-add-force-geniro" "git add -f on .geniro/ paths makes ignored files appear in the IDE's Source Control panel — one click of 'Discard All Changes' then deletes them. To track .geniro/ subdirs, negate them in .gitignore instead (e.g. \`!.geniro/actions/\` and \`!.geniro/actions/**\`)."
      fi
    fi
  fi
fi

exit 0
