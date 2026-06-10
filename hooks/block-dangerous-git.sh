#!/usr/bin/env bash
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
#              clean-fd, checkout-mass-discard, restore-mass-discard,
#              update-ref-delete, filter-branch

set -euo pipefail

# Fail open but LOUDLY if jq is missing: without it the guard cannot inspect
# commands, and a silent exit 0 would leave the user believing the guard is active.
if ! command -v jq >/dev/null 2>&1; then
  printf '{"systemMessage":"Geniro guard inactive: jq not found on PATH, so destructive git commands are NOT being checked. Install jq to restore the guard."}\n'
  exit 0
fi

INPUT=$(cat)
COMMAND=$(printf '%s' "$INPUT" | jq -r '.tool_input.command // ""' 2>/dev/null || echo "")

if [ -z "$COMMAND" ]; then
  exit 0
fi

# Pad the command with leading/trailing whitespace so flag matchers like
# [[:space:]]-f[[:space:]] reliably hit -f even at start/end of string.
# Join backslash-newline line continuations first (the shell glues them into one
# logical command: `git \<newline>push -f` runs as `git push -f`), then collapse
# remaining newlines to spaces so multi-line commands (heredocs, embedded \n)
# don't slip past line-oriented grep matching — a force-push on line 1 of a
# multi-line command must still trigger the block.
# The force-push / branch-delete / clean matchers below bound their match to the
# span of the relevant git subcommand (up to the next &/;/| separator) so a flag
# from a separate command chained after it (e.g. `git branch --list && gcc -DFOO`,
# `git clean -n && tar -fd`) does not false-positive.
JOINED="${COMMAND//\\$'\n'/ }"
PADDED=" ${JOINED//$'\n'/ } "

# Strip git GLOBAL options (`git -C <path> push`, `git -c k=v push`, --git-dir/
# --work-tree/--namespace, pager flags) so the subcommand matchers below see
# `git <subcommand>` contiguously. Without this, `git -C /repo push --force`
# evades every `git[[:space:]]+<subcommand>` matcher.
PADDED=$(printf '%s' "$PADDED" | sed -E 's/git([[:space:]]+(-C[[:space:]]+[^[:space:]]+|-c[[:space:]]+[^[:space:]]+|--git-dir(=[^[:space:]]+|[[:space:]]+[^[:space:]]+)|--work-tree(=[^[:space:]]+|[[:space:]]+[^[:space:]]+)|--namespace(=[^[:space:]]+|[[:space:]]+[^[:space:]]+)|-P|--no-pager|-p|--paginate|--no-optional-locks|--literal-pathspecs))+/git/g')

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
  if echo "$PADDED" | grep -qE 'git[[:space:]]+push[^&;|]*--force-with-lease'; then
    block "force-push-with-lease" "git push --force-with-lease can still overwrite remote work if your local ref is stale"
  fi
fi

# 2. force-push (--force or -f as a flag, NOT part of another long flag like --force-if-includes)
if ! is_allowed "force-push"; then
  # Trailing anchor ([[:space:];&|]|$): a separator can abut the flag with no
  # space (`git push --force;echo done`), so whitespace-only anchors would miss
  # the most common chained spellings.
  if echo "$PADDED" | grep -qE 'git[[:space:]]+push[^&;|]*[[:space:]]--force([[:space:];&|]|$)'; then
    block "force-push" "git push --force overwrites remote history"
  fi
  if echo "$PADDED" | grep -qE 'git[[:space:]]+push[^&;|]*[[:space:]]-f([[:space:];&|]|$)'; then
    block "force-push" "git push -f overwrites remote history"
  fi
  # Combined short flags like -fu (force + set-upstream)
  if echo "$PADDED" | grep -qE 'git[[:space:]]+push[^&;|]*[[:space:]]-[a-zA-Z]*f[a-zA-Z]*([[:space:];&|]|$)'; then
    block "force-push" "git push with combined -f flag overwrites remote history"
  fi
  # Plus-prefixed refspec (e.g. `git push origin +main`) forces the push with no flag.
  if echo "$PADDED" | grep -qE 'git[[:space:]]+push[^&;|]*[[:space:]][+][^[:space:]]+'; then
    block "force-push" "git push with a +refspec (e.g. +main) force-overwrites remote history"
  fi
fi

# 3. reset --hard — span-bounded to the `git reset` command itself, so a --hard*
#    token from a DIFFERENT command chained after it (e.g. `git reset HEAD~1 &&
#    npm run build -- --hardened`) cannot false-positive.
if ! is_allowed "reset-hard"; then
  if echo "$PADDED" | grep -qE 'git[[:space:]]+reset[^&;|]*[[:space:]]--hard([[:space:];&|]|$)'; then
    block "reset-hard" "git reset --hard discards uncommitted work irreversibly"
  fi
fi

# 4. branch -D / --delete --force
if ! is_allowed "branch-delete-force"; then
  # Extract the `git branch ...` span (up to the next &/;/| separator) and match
  # flags only within it, so a -D/--force from a different command chained after
  # `git branch` (e.g. `git branch --list && gcc -DFOO`) cannot false-positive.
  BRANCH_SPAN=$(echo "$PADDED" | grep -oE 'git[[:space:]]+branch[^&;|]*' || true)
  if [ -n "$BRANCH_SPAN" ]; then
    # Match -D whether standalone or combined into a short-flag cluster (-Df, -fD,
    # -rD, ...), mirroring the force-push combined-flag matcher. `-D` always means
    # force-delete in `git branch`; the lowercase `-d` (safe delete of a merged
    # branch) has no uppercase D and is intentionally not matched.
    if echo "$BRANCH_SPAN" | grep -qE '[[:space:]]-[a-zA-Z]*D[a-zA-Z]*([[:space:]]|$)'; then
      block "branch-delete-force" "git branch -D (including combined flags like -Df) force-deletes unmerged branches"
    fi
    if echo "$BRANCH_SPAN" | grep -qE '[[:space:]]--delete([[:space:]]|$)' && \
       echo "$BRANCH_SPAN" | grep -qE '[[:space:]]--force([[:space:]]|$)'; then
      block "branch-delete-force" "git branch --delete --force force-deletes unmerged branches"
    fi
  fi
fi

# 5. clean -fd (and variants)
if ! is_allowed "clean-fd"; then
  # Extract each `git clean ...` span and match flags only within it, so flags
  # from a different command chained after `git clean` (e.g. `git clean -n &&
  # tar -fd`) cannot false-positive. Spans are evaluated one per line so a
  # dry-run span cannot mask a destructive sibling in the same command
  # (`git clean -n && git clean -fd`).
  CLEAN_SPANS=$(echo "$PADDED" | grep -oE 'git[[:space:]]+clean[^&;|]*' || true)
  while IFS= read -r CLEAN_SPAN; do
    [ -z "$CLEAN_SPAN" ] && continue
    # git treats -n/--dry-run as a preview even when combined with -f/-d —
    # nothing is deleted, so a dry-run span is allowed.
    if echo "$CLEAN_SPAN" | grep -qE '[[:space:]]-[a-zA-Z]*n[a-zA-Z]*([[:space:]]|$)|[[:space:]]--dry-run([[:space:]]|$)'; then
      continue
    fi
    # Short flag containing BOTH f and d in any order: -fd, -df, -fdx, -ffd, -dfx
    if echo "$CLEAN_SPAN" | grep -qE '[[:space:]]-[a-zA-Z]*f[a-zA-Z]*d[a-zA-Z]*([[:space:]]|$)'; then
      block "clean-fd" "git clean -fd deletes untracked files and directories"
    fi
    if echo "$CLEAN_SPAN" | grep -qE '[[:space:]]-[a-zA-Z]*d[a-zA-Z]*f[a-zA-Z]*([[:space:]]|$)'; then
      block "clean-fd" "git clean -df deletes untracked files and directories"
    fi
    # Separate tokens: a standalone -f/--force AND a standalone -d (in either order)
    if echo "$CLEAN_SPAN" | grep -qE '[[:space:]](-f|--force)([[:space:]]|$)' && \
       echo "$CLEAN_SPAN" | grep -qE '[[:space:]]-d([[:space:]]|$)'; then
      block "clean-fd" "git clean -f -d deletes untracked files and directories"
    fi
  done <<< "$CLEAN_SPANS"
fi

# 6. checkout mass-discard. A standalone `.` (or `./`, or a bare `*` token) as a
#    checkout pathspec overwrites the whole working tree — with or without `--`,
#    with or without a ref before it (`git checkout .`, `git checkout HEAD -- .`).
#    Single-file forms (`git checkout -- src/file.js`, `git checkout .gitignore`)
#    stay allowed: the dot must be a standalone token, not part of a filename.
if ! is_allowed "checkout-mass-discard"; then
  if echo "$PADDED" | grep -qE 'git[[:space:]]+checkout[^&;|]*[[:space:]]\./?([[:space:];&|]|$)'; then
    block "checkout-mass-discard" "git checkout with a bare . pathspec discards ALL uncommitted changes"
  fi
  if echo "$PADDED" | grep -qE 'git[[:space:]]+checkout[^&;|]*[[:space:]]\*'; then
    block "checkout-mass-discard" "git checkout with a * pathspec discards ALL uncommitted changes"
  fi
fi

# 7. restore mass-discard. Same standalone-token rule as checkout: a bare `.`,
#    `./`, or `*` pathspec anywhere in the `git restore` span (with or without
#    --staged / -s <ref> before it) discards or unstages everything.
if ! is_allowed "restore-mass-discard"; then
  if echo "$PADDED" | grep -qE 'git[[:space:]]+restore[^&;|]*[[:space:]]\./?([[:space:];&|]|$)'; then
    block "restore-mass-discard" "git restore with a bare . pathspec discards ALL unstaged changes (or unstages everything with --staged)"
  fi
  if echo "$PADDED" | grep -qE 'git[[:space:]]+restore[^&;|]*[[:space:]]\*'; then
    block "restore-mass-discard" "git restore with a * pathspec discards ALL unstaged changes (or unstages everything with --staged)"
  fi
fi

# 8. update-ref -d / --delete (other flags like --no-deref may precede the
#    delete flag, so the span is bounded rather than position-anchored)
if ! is_allowed "update-ref-delete"; then
  if echo "$PADDED" | grep -qE 'git[[:space:]]+update-ref[^&;|]*[[:space:]](-d|--delete)([[:space:];&|]|$)'; then
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
