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

# Shell indirection: `sh -c "<payload>"` / `eval "<payload>"` pass <payload> as
# an ARGUMENT, and `echo "<payload>" | bash` / `bash <<EOF … EOF` pass it on
# STDIN. All four run <payload> as a command, but the quote-scrub below would
# treat it as data — and the heredoc scrub above deletes it outright — so a
# destructive op inside would never be seen. Extraction is single-sourced in
# lib/write-vectors.sh; the inline fallback keeps the guard recursing on a
# vendored install shipping hooks/ without lib/ — a missing helper must never
# make this guard fail open. The fallback is a VERBATIM copy of the canonical
# function (see its GENIRO-VENDORED markers); edit both or neither.
_geniro_wv_helper="${CLAUDE_PLUGIN_ROOT:-.}/lib/write-vectors.sh"
if [ -f "$_geniro_wv_helper" ]; then
  # shellcheck source=/dev/null
  source "$_geniro_wv_helper" 2>/dev/null || true
fi
if ! command -v _geniro_extract_inner_payloads >/dev/null 2>&1; then
# GENIRO-VENDORED-BEGIN _geniro_extract_inner_payloads
_geniro_extract_inner_payloads() {
  local cmd="${1:-}"
  local raw="${2:-}"
  if [ -z "$cmd" ] && [ -z "$raw" ]; then
    return 0
  fi
  local _m _pl _lit

  # ONE shell-word matcher for every arm. The wrapper prefix consumes its own
  # flags, `VAR=value` assignments, durations and `{}` placeholders — never an
  # arbitrary word, which would let any two-word command read as a shell.
  local _wv_pfx='((sudo|doas|command|env|exec|nohup|nice|timeout|stdbuf|ionice|xargs)([[:space:]]+(-[^[:space:];|&<>]+|[A-Za-z_][A-Za-z0-9_]*=[^[:space:];|&<>]*|[0-9]+[smhd]?|[{}]+))*[[:space:]]+)*'
  local _wv_shq='["'\'']?'
  local _wv_sh="${_wv_pfx}${_wv_shq}"'([^[:space:];|&<>"'\'']*/)?(sh|bash|zsh|dash|ksh|ash)'"${_wv_shq}"
  # One quoted literal; and the payload operand form, which may also be bare.
  local _wv_lit='("[^"]*"|'\''[^'\'']*'\'')'
  local _wv_arg='("[^"]*"|'\''[^'\'']*'\''|[^[:space:];|&]+)'

  # Arm 1 — interpreter `-c` payload.
  while IFS= read -r _m; do
    [ -z "$_m" ] && continue
    _pl=$(printf '%s' "$_m" | sed -E 's/^.*[[:space:]]-[A-Za-z]*c[A-Za-z]*[[:space:]]+//')
    _pl="${_pl#\"}"; _pl="${_pl%\"}"
    _pl="${_pl#\'}"; _pl="${_pl%\'}"
    [ -n "$_pl" ] && printf '%s\n' "$_pl"
  done <<< "$(printf '%s\n' "$cmd" | grep -oE '(^|[^[:alnum:]_])'"${_wv_sh}"'[[:space:]]+-[A-Za-z]*c[A-Za-z]*[[:space:]]+'"${_wv_arg}" 2>/dev/null || true)"

  # Arm 2 — `eval` payload. The preceding-character class excludes `-` so a long
  # option belonging to another tool (`node --eval`, `perl --eval`) is not read
  # as the shell builtin; those are interpreter payloads, not shell commands.
  while IFS= read -r _m; do
    [ -z "$_m" ] && continue
    _pl=$(printf '%s' "$_m" | sed -E 's/^[^[:alnum:]_]?eval[[:space:]]+//')
    _pl="${_pl#\"}"; _pl="${_pl%\"}"
    _pl="${_pl#\'}"; _pl="${_pl%\'}"
    [ -n "$_pl" ] && printf '%s\n' "$_pl"
  done <<< "$(printf '%s\n' "$cmd" | grep -oE '(^|[^[:alnum:]_/-])eval[[:space:]]+'"${_wv_arg}" 2>/dev/null || true)"

  # Arm 3 — a quoted literal piped into a shell. `echo "<program>" | bash`
  # feeds <program> on stdin, so it is neither a `-c` argument nor an `eval`
  # operand, and the guard's quote-scrub blanks it as data. The right-hand side
  # must carry no flag cluster containing `c` (that spelling is arm 1's, and
  # with -c the shell ignores stdin). Only a QUOTED left-hand literal is
  # extractable: a producer that COMPUTES its program (a file read, a network
  # download) carries no literal this scan can read — the download spelling is
  # hooks/security-pattern-check.sh's sec-curl-pipe-sh pattern instead.
  while IFS= read -r _m; do
    [ -z "$_m" ] && continue
    # Drop from the LAST pipe, so a `|` inside the literal survives.
    _pl=$(printf '%s' "$_m" | sed -E 's/[[:space:]]*[|][^|]*$//')
    _pl="${_pl#\"}"; _pl="${_pl%\"}"
    _pl="${_pl#\'}"; _pl="${_pl%\'}"
    [ -n "$_pl" ] && printf '%s\n' "$_pl"
  done <<< "$(printf '%s\n' "$cmd" | grep -oE "${_wv_lit}"'[^|"'\'']*\|[[:space:]]*'"${_wv_sh}"'([[:space:]]+-[a-bd-zA-BD-Z0-9]+)*[[:space:]]*($|[;&|])' 2>/dev/null || true)"

  # Arm 4 — a heredoc body fed to a shell (`bash <<EOF … EOF`, `cat <<EOF | sh`).
  # This is the mirror image of arm 3: the body is stdin, and every guard's
  # heredoc scrub deletes it BEFORE extraction because a heredoc is data in every
  # other position (`cat > notes.md <<EOF`). So the body is re-derived here from
  # the RAW command, and emitted only when the opener line names a shell as a
  # command word. One body LINE per payload: the guards match per line and per
  # `;`-bounded span, and joining the body would let a single `#` comment line
  # swallow the commands after it. The shell-word matcher reaches awk through the
  # environment, not `-v`, because awk processes escape sequences in a `-v`
  # assignment and would eat the regex's own backslashes.
  if [ -n "$raw" ]; then
    printf '%s\n' "$raw" | GENIRO_WV_SHRE='(^|[|;&][[:space:]]*|[[:space:]])'"${_wv_sh}"'([[:space:]]|$)' awk '
      hd {
        line = $0
        if (dash) sub(/^\t+/, "", line)
        if (line == tag) { hd = 0; next }
        if (emit) print line
        next
      }
      match($0, /<<-?[[:space:]]*["'\'']?[A-Za-z_][A-Za-z0-9_]*/) {
        tag = substr($0, RSTART, RLENGTH)
        dash = (tag ~ /^<<-/)
        sub(/^<<-?[[:space:]]*/, "", tag)
        gsub(/["'\'']/, "", tag)
        hd = 1
        emit = ($0 ~ ENVIRON["GENIRO_WV_SHRE"])
        next
      }
    ' 2>/dev/null || true
  fi

  # Arm 5 — a program fed to a shell through process substitution
  # (`bash <(echo "<program>")`, `sh -s < <(printf '<program>')`). The shell reads
  # it from the /dev/fd path the substitution names, so it carries no `-c`, no
  # pipe into the shell and no heredoc — arms 1-4 all miss it. Every quoted
  # literal inside the substitution is a candidate program, the same limit arm 3
  # carries: a substitution that COMPUTES its program leaves nothing to read.
  while IFS= read -r _m; do
    [ -z "$_m" ] && continue
    while IFS= read -r _lit; do
      [ -z "$_lit" ] && continue
      _pl="$_lit"
      _pl="${_pl#\"}"; _pl="${_pl%\"}"
      _pl="${_pl#\'}"; _pl="${_pl%\'}"
      [ -n "$_pl" ] && printf '%s\n' "$_pl"
    done <<< "$(printf '%s' "$_m" | grep -oE "${_wv_lit}" 2>/dev/null || true)"
  done <<< "$(printf '%s\n' "$cmd" | grep -oE '(^|[^[:alnum:]_])'"${_wv_sh}"'[^|;&]*[<>]\([^)]*\)' 2>/dev/null || true)"

  # Arm 6 — an interpreter handing a program to a shell. `os.system('<program>')`,
  # `subprocess.run('<program>', shell=True)` and `child_process.execSync(...)`
  # spawn a real shell, but the interpreter is not one, so no arm above sees the
  # call — and the program is not an interpreter FILE op either, so family B below
  # misses it too. That makes any interpreter a laundering channel for every
  # payload the guards block directly. The quoted argument IS the shell command.
  #
  # Gated on an interpreter COMMAND WORD, because the same text is inert without
  # one: `echo "os.system('rm -rf x')" > notes.md` authors a file, it does not
  # shell out, and blocking it would be a false positive on ordinary code
  # authoring. Nothing extractable is lost — a shell-out inside a script FILE
  # carries no literal in the command either way.
  if printf '%s' "$cmd" | grep -qE '(^|[|;&[:space:]]|/)(python[0-9.]*|node|bun|bunx|deno|tsx|perl|ruby|php|lua|tclsh|Rscript)([[:space:]]|$)'; then
    # A dot is allowed before the op name because that is how the ops are normally
    # reached (`require('child_process').execSync(…)`); the cost is that a JS
    # `re.exec("s")` also yields its argument, which re-scans as an inert word.
    local _wv_shellout='(os\.(system|popen)|subprocess\.[A-Za-z_]+|Kernel\.system|IO\.popen|Open3\.[a-z_]+|exec(Sync|FileSync)?|system|popen|shell_exec|passthru|proc_open)'
    while IFS= read -r _m; do
      [ -z "$_m" ] && continue
      _pl=$(printf '%s' "$_m" | sed -E 's/^[^(]*\([[:space:]]*//')
      _pl="${_pl#\\}"
      _pl="${_pl#\"}"; _pl="${_pl%\"}"
      _pl="${_pl#\'}"; _pl="${_pl%\'}"
      _pl="${_pl%\\}"
      [ -n "$_pl" ] && printf '%s\n' "$_pl"
    done <<< "$(printf '%s\n' "$cmd" | grep -oE '(^|[^[:alnum:]_])'"${_wv_shellout}"'[[:space:]]*\([[:space:]]*\\?'"${_wv_lit}" 2>/dev/null || true)"

    # Ruby's backtick literal is the same shell-out with no call syntax at all.
    # Narrowed further to a `ruby` command word: elsewhere a backtick span is
    # ordinary shell command substitution, already visible to the guards as
    # syntax, and re-extracting it would only add noise.
    if printf '%s' "$cmd" | grep -qE '(^|[|;&[:space:]]|/)ruby([[:space:]]|$)'; then
      while IFS= read -r _m; do
        [ -z "$_m" ] && continue
        _pl=$(printf '%s' "$_m" | sed -E 's/^`//; s/`$//')
        [ -n "$_pl" ] && printf '%s\n' "$_pl"
      done <<< "$(printf '%s\n' "$cmd" | grep -oE '`[^`]*`' 2>/dev/null || true)"
    fi
  fi

  return 0
}
# GENIRO-VENDORED-END _geniro_extract_inner_payloads
fi

# Re-run THIS guard on each extracted payload (unblanked); a block inside
# propagates out. Nested indirection terminates because each payload is
# strictly shorter than the command it came from. Arms 1-3 read the
# heredoc-scrubbed text; arm 4 needs the RAW command, whose heredoc bodies the
# scrub dropped.
_geniro_self="${BASH_SOURCE[0]:-$0}"
INNER_PAYLOADS=$(_geniro_extract_inner_payloads "$SCRUBBED" "$COMMAND")
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
  # allow_patterns entries name exact pattern IDs. The membership test below is a
  # substring probe over the space-joined list, so a single entry that CARRIES
  # whitespace ("harmless write-env alsoharmless") would silently enable every ID
  # spelled inside it. Reject those at load rather than weaken the probe.
  ALLOWED=$(jq -r '.allow_patterns[]? | select(type == "string" and (test("[[:space:]]") | not))' "$SAFETY_FILE" 2>/dev/null | tr '\n' ' ' || echo "")
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
