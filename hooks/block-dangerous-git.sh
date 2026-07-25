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
# Pattern IDs: force-push, force-push-with-lease, push-delete, reset-hard,
#              branch-delete-force, clean-fd, checkout-mass-discard,
#              restore-mass-discard, update-ref-delete, filter-branch

set -euo pipefail

# Fail open but LOUDLY if jq is missing: without it the guard cannot inspect
# commands, and a silent exit 0 would leave the user believing the guard is active.
if ! command -v jq >/dev/null 2>&1; then
  # Data-loss guard: without jq we cannot parse the command out of the tool JSON,
  # but a raw scan of the payload for the highest-signal destructive tokens still
  # blocks the worst cases before failing open. Coarse by design (it also sees a
  # token inside a quoted string) — accepted for a rarely-hit degraded path where
  # blocking a real force-push matters more than a false positive on prose.
  RAW=$(cat)
  if printf '%s' "$RAW" | grep -qE '\-\-force(-with-lease)?|reset[[:space:]]+--hard|filter-branch'; then
    echo "Security blocked [jqless-fallback]: a destructive git token (--force / reset --hard / filter-branch) was seen and jq is unavailable, so only a coarse raw-text check ran. Install jq to restore full command parsing." >&2
    exit 2
  fi
  printf '{"systemMessage":"Geniro guard inactive: jq not found on PATH, so destructive git commands are NOT being checked. Install jq to restore the guard."}\n'
  exit 0
fi

INPUT=$(cat)
COMMAND=$(printf '%s' "$INPUT" | jq -r '.tool_input.command // ""' 2>/dev/null || echo "")

if [ -z "$COMMAND" ]; then
  exit 0
fi

# Heredoc bodies are DATA, not shell syntax — a `git push --force` mentioned
# inside one is text, not a command. Drop body lines (between <<TAG / <<-TAG /
# <<'TAG' and the closing TAG) before any matching; the line carrying the <<
# operator itself is kept. Mirrors file-protection.sh.
SCRUBBED=$(printf '%s\n' "$COMMAND" | awk '
  hd {
    line = $0
    if (dash) sub(/^\t+/, "", line)   # <<- strips leading TABS from the terminator
    if (line == tag) hd = 0
    next
  }
  match($0, /<<-?[[:space:]]*["'\'']?[A-Za-z_][A-Za-z0-9_]*/) {
    tag = substr($0, RSTART, RLENGTH)
    dash = (tag ~ /^<<-/)
    sub(/^<<-?[[:space:]]*/, "", tag)
    gsub(/["'\'']/, "", tag)
    hd = 1
    print
    next
  }
  { print }
')

# Interpreter indirection: `sh -c "<payload>"` (or bash/zsh/dash -lc, ...) and
# `eval "<payload>"` run <payload> as a command, but the quote-scrub below would
# treat it as data and miss a destructive op inside it. Extraction is
# single-sourced in lib/write-vectors.sh; the inline fallback keeps the guard
# recursing on a vendored install shipping hooks/ without lib/ — a missing
# helper must never make this guard fail open.
_geniro_wv_helper="${CLAUDE_PLUGIN_ROOT:-.}/lib/write-vectors.sh"
if [ -f "$_geniro_wv_helper" ]; then
  # shellcheck source=/dev/null
  source "$_geniro_wv_helper" 2>/dev/null || true
fi
if ! command -v _geniro_extract_inner_payloads >/dev/null 2>&1; then
  _geniro_extract_inner_payloads() {
    local cmd="${1:-}"
    if [ -z "$cmd" ]; then return 0; fi
    local _m _pl
    while IFS= read -r _m; do
      [ -z "$_m" ] && continue
      _pl=$(printf '%s' "$_m" | sed -E 's/^.*[[:space:]]-[A-Za-z]*c[A-Za-z]*[[:space:]]+//')
      _pl="${_pl#\"}"; _pl="${_pl%\"}"; _pl="${_pl#\'}"; _pl="${_pl%\'}"
      [ -n "$_pl" ] && printf '%s\n' "$_pl"
    done <<< "$(printf '%s\n' "$cmd" | grep -oE '(^|[^[:alnum:]_/])(sh|bash|zsh|dash|ksh|ash)[[:space:]]+-[A-Za-z]*c[A-Za-z]*[[:space:]]+("[^"]*"|'\''[^'\'']*'\''|[^[:space:];|&]+)' 2>/dev/null || true)"
    while IFS= read -r _m; do
      [ -z "$_m" ] && continue
      _pl=$(printf '%s' "$_m" | sed -E 's/^[^[:alnum:]_]?eval[[:space:]]+//')
      _pl="${_pl#\"}"; _pl="${_pl%\"}"; _pl="${_pl#\'}"; _pl="${_pl%\'}"
      [ -n "$_pl" ] && printf '%s\n' "$_pl"
    done <<< "$(printf '%s\n' "$cmd" | grep -oE '(^|[^[:alnum:]_/-])eval[[:space:]]+("[^"]*"|'\''[^'\'']*'\''|[^[:space:];|&]+)' 2>/dev/null || true)"
    return 0
  }
fi

# Re-run THIS guard on each extracted payload (unblanked); a block inside
# propagates out. Nested indirection terminates because each payload is
# strictly shorter than the command it came from.
_geniro_self="${BASH_SOURCE[0]:-$0}"
INNER_PAYLOADS=$(_geniro_extract_inner_payloads "$SCRUBBED")
if [ -n "$INNER_PAYLOADS" ]; then
  while IFS= read -r _pl; do
    [ -z "$_pl" ] && continue
    if ! printf '%s' "$_pl" | jq -Rs '{tool_name: "Bash", tool_input: {command: .}}' | bash "$_geniro_self"; then
      exit 2
    fi
  done <<< "$INNER_PAYLOADS"
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
JOINED="${SCRUBBED//\\$'\n'/ }"
PADDED=" ${JOINED//$'\n'/ } "

# Strip git GLOBAL options (`git -C <path> push`, `git -c k=v push`, --git-dir/
# --work-tree/--namespace, pager flags) so the subcommand matchers below see
# `git <subcommand>` contiguously. Without this, `git -C /repo push --force`
# evades every `git[[:space:]]+<subcommand>` matcher.
#
# This MUST run BEFORE the quote-blank below: a quoted global-option operand
# (`git -C "/my repo" push --force`) is consumed here as one unit only while its
# quotes are intact. If quote-blanking ran first it would erase the path to a
# space, and `-C[[:space:]]+<token>` would then swallow the following SUBCOMMAND
# (`push`) instead, leaving `git --force` and bypassing every matcher. The
# operand alternative matches a double- or single-quoted span (which may contain
# spaces) before falling back to a bare token.
_op='("[^"]*"|'\''[^'\'']*'\''|[^[:space:]]+)'
PADDED=$(printf '%s' "$PADDED" | sed -E "s/git([[:space:]]+(-C[[:space:]]+${_op}|-c[[:space:]]+${_op}|--git-dir(=${_op}|[[:space:]]+${_op})|--work-tree(=${_op}|[[:space:]]+${_op})|--namespace(=${_op}|[[:space:]]+${_op})|--exec-path(=${_op}|[[:space:]]+${_op})|--config-env(=${_op}|[[:space:]]+${_op})|--attr-source(=${_op}|[[:space:]]+${_op})|-P|--no-pager|-p|--paginate|--no-optional-locks|--literal-pathspecs))+/git/g")

# Quoted string literals are DATA, not commands — with two exceptions handled by
# pass ordering. Pass A UNQUOTES a whitespace-free quoted token (a quoted flag or
# subcommand like "--force"): such a token is a single shell word, so unquoting
# it re-exposes a destructive op that was smuggled past the matchers by quoting
# its flag (`git push origin main "--force"`). Pass B then blanks the remaining
# quoted literals — those all contain whitespace or a separator, i.e. prose
# (`echo "run git push --force later"`), which must never block. Pass B excludes
# ; & | from its span so an unbalanced apostrophe in benign prose
# (`echo can't wait && git push --force && echo don't`) cannot pair across a
# separator and swallow a real destructive command sitting between two quotes.
PADDED=$(printf '%s' "$PADDED" | sed -E "s/\"([^\"[:space:]]*)\"/\1/g; s/'([^'[:space:]]*)'/\1/g; s/'[^';&|]*'/ /g; s/\"[^\";&|]*\"/ /g")

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

# 2b. push-delete — remote-branch deletion via `git push <remote> --delete/-d
#     <branch>` or the colon delete-refspec (`git push origin :branch`). Bounded
#     to the `git push` span so a -d/--delete from a chained command can't false-
#     positive. The lone `-d` form is matched as a standalone short flag (combined
#     clusters like -df are not a valid push delete spelling); the colon refspec
#     matches a token whose source side is empty (`:dst`).
if ! is_allowed "push-delete"; then
  PUSH_SPAN=$(echo "$PADDED" | grep -oE 'git[[:space:]]+push[^&;|]*' || true)
  if [ -n "$PUSH_SPAN" ]; then
    if echo "$PUSH_SPAN" | grep -qE '[[:space:]]--delete([[:space:];&|]|$)'; then
      block "push-delete" "git push --delete removes a branch on the remote"
    fi
    if echo "$PUSH_SPAN" | grep -qE '[[:space:]]-d([[:space:];&|]|$)'; then
      block "push-delete" "git push -d removes a branch on the remote"
    fi
    if echo "$PUSH_SPAN" | grep -qE '[[:space:]]:[^[:space:];&|]+'; then
      block "push-delete" "git push with a :refspec (e.g. origin :branch) deletes that branch on the remote"
    fi
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
