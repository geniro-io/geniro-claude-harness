#!/bin/bash
# block-dangerous-git.sh
# PreToolUse hook for Bash - blocks destructive git operations
#
# Conservative patterns: blocks force-pushes, hard resets, force branch deletes,
# aggressive cleans, mass-discard checkouts/restores. Allows normal git workflow
# (push, checkout, soft reset, etc.).
#
# Per-project allowlist: .geniro/safety.json (in cwd or any ancestor) can opt out
# of specific patterns by listing pattern IDs in the "allow_patterns" array.
#
# Schema:
#   {
#     "allow_patterns": ["force-push-with-lease", "clean-fd"]
#   }
#
# Pattern IDs: force-push, force-push-with-lease, reset-hard, branch-delete-force,
#              clean-fd, checkout-mass-discard, restore-mass-discard, rebase-onto-hard,
#              update-ref-delete, filter-branch

set -euo pipefail

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // ""' 2>/dev/null || echo "")

if [ -z "$COMMAND" ]; then
  exit 0
fi

# Pad the command with leading/trailing whitespace so flag matchers like
# [[:space:]]-f[[:space:]] reliably hit -f even at start/end of string.
# Also collapse newlines to spaces so multi-line commands (heredocs, line-continuation,
# embedded \n) don't slip past line-oriented grep matching — a force-push on line 1
# of a multi-line command must still trigger the block.
PADDED=" ${COMMAND//$'\n'/ } "

# Find the nearest .geniro/safety.json walking up from cwd
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
  echo "Security blocked [$pattern_id]: $message" >&2
  echo "Command: $COMMAND" >&2
  if [ -n "$SAFETY_FILE" ]; then
    echo "To allow this pattern, add \"$pattern_id\" to allow_patterns in $SAFETY_FILE" >&2
  else
    echo "To allow this pattern in this project, create .geniro/safety.json with: {\"allow_patterns\": [\"$pattern_id\"]}" >&2
  fi
  exit 2
}

# Each check: id, regex (POSIX ERE on the padded command), message.
# Order matters: more specific patterns first.

# 1. force-push-with-lease — must come before generic force-push
if ! is_allowed "force-push-with-lease"; then
  if echo "$PADDED" | grep -qE 'git[[:space:]]+push.*--force-with-lease'; then
    block "force-push-with-lease" "git push --force-with-lease can still overwrite remote work if your local ref is stale"
  fi
fi

# 2. force-push (--force or -f as a flag, NOT part of another long flag like --force-if-includes)
if ! is_allowed "force-push"; then
  if echo "$PADDED" | grep -qE 'git[[:space:]]+push.*[[:space:]]--force[[:space:]]'; then
    block "force-push" "git push --force overwrites remote history"
  fi
  if echo "$PADDED" | grep -qE 'git[[:space:]]+push.*[[:space:]]-f[[:space:]]'; then
    block "force-push" "git push -f overwrites remote history"
  fi
  # Combined short flags like -fu (force + set-upstream)
  if echo "$PADDED" | grep -qE 'git[[:space:]]+push.*[[:space:]]-[a-zA-Z]*f[a-zA-Z]*[[:space:]]'; then
    block "force-push" "git push with combined -f flag overwrites remote history"
  fi
fi

# 3. reset --hard
if ! is_allowed "reset-hard"; then
  if echo "$PADDED" | grep -qE 'git[[:space:]]+reset[[:space:]].*--hard'; then
    block "reset-hard" "git reset --hard discards uncommitted work irreversibly"
  fi
fi

# Helper: does the padded command invoke a given git subcommand?
is_git_subcommand() {
  local sub="$1"
  echo "$PADDED" | grep -qE "git[[:space:]]+${sub}[[:space:]]"
}

# 4. branch -D / --delete --force
if ! is_allowed "branch-delete-force"; then
  if is_git_subcommand "branch"; then
    if echo "$PADDED" | grep -qE '[[:space:]]-D[[:space:]]'; then
      block "branch-delete-force" "git branch -D force-deletes unmerged branches"
    fi
    if echo "$PADDED" | grep -qE '[[:space:]]--delete[[:space:]]' && \
       echo "$PADDED" | grep -qE '[[:space:]]--force[[:space:]]'; then
      block "branch-delete-force" "git branch --delete --force force-deletes unmerged branches"
    fi
  fi
fi

# 5. clean -fd (and variants)
if ! is_allowed "clean-fd"; then
  if is_git_subcommand "clean"; then
    # Short flag containing BOTH f and d in any order: -fd, -df, -fdx, -ffd, -dfx
    if echo "$PADDED" | grep -qE '[[:space:]]-[a-zA-Z]*f[a-zA-Z]*d[a-zA-Z]*[[:space:]]'; then
      block "clean-fd" "git clean -fd deletes untracked files and directories"
    fi
    if echo "$PADDED" | grep -qE '[[:space:]]-[a-zA-Z]*d[a-zA-Z]*f[a-zA-Z]*[[:space:]]'; then
      block "clean-fd" "git clean -df deletes untracked files and directories"
    fi
    # Long-form: --force AND -d (in either order)
    if echo "$PADDED" | grep -qE '[[:space:]]--force[[:space:]]' && \
       echo "$PADDED" | grep -qE '[[:space:]]-d[[:space:]]'; then
      block "clean-fd" "git clean --force -d deletes untracked files and directories"
    fi
  fi
fi

# 6. checkout -- . / checkout -- *
if ! is_allowed "checkout-mass-discard"; then
  if echo "$PADDED" | grep -qE 'git[[:space:]]+checkout[[:space:]]+--[[:space:]]+\.[[:space:]]'; then
    block "checkout-mass-discard" "git checkout -- . discards ALL uncommitted changes"
  fi
  if echo "$PADDED" | grep -qE 'git[[:space:]]+checkout[[:space:]]+--[[:space:]]+\*'; then
    block "checkout-mass-discard" "git checkout -- * discards ALL uncommitted changes"
  fi
fi

# 7. restore . / restore --staged .
if ! is_allowed "restore-mass-discard"; then
  if echo "$PADDED" | grep -qE 'git[[:space:]]+restore[[:space:]]+\.[[:space:]]'; then
    block "restore-mass-discard" "git restore . discards ALL unstaged changes"
  fi
  if echo "$PADDED" | grep -qE 'git[[:space:]]+restore[[:space:]]+\*'; then
    block "restore-mass-discard" "git restore * discards ALL unstaged changes"
  fi
  if echo "$PADDED" | grep -qE 'git[[:space:]]+restore[[:space:]]+--staged[[:space:]]+\.[[:space:]]'; then
    block "restore-mass-discard" "git restore --staged . unstages ALL changes"
  fi
  if echo "$PADDED" | grep -qE 'git[[:space:]]+restore[[:space:]]+--staged[[:space:]]+\*'; then
    block "restore-mass-discard" "git restore --staged * unstages ALL changes"
  fi
fi

# 8. update-ref -d
if ! is_allowed "update-ref-delete"; then
  if echo "$PADDED" | grep -qE 'git[[:space:]]+update-ref[[:space:]]+-d'; then
    block "update-ref-delete" "git update-ref -d deletes refs directly, bypassing reflog protection"
  fi
fi

# 9. filter-branch
if ! is_allowed "filter-branch"; then
  if echo "$PADDED" | grep -qE 'git[[:space:]]+filter-branch'; then
    block "filter-branch" "git filter-branch rewrites entire history; use git filter-repo or BFG instead and only with team coordination"
  fi
fi

exit 0
