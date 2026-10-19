#!/usr/bin/env bash
# block-geniro-force-add.sh
# PreToolUse hook for Bash and Monitor — blocks `git add -f` / `--force` (and
# `git stage`, git's synonym for `add`) and the plumbing twin `git update-index
# --add` on .geniro/ paths.
#
# Force-adding a gitignored file puts it in the IDE's Source Control panel,
# where one "Discard All Changes" click deletes it (real incident: a Cursor SCM
# discard wiped force-added .geniro/actions/*.md). To track a .geniro/ subdir,
# negate it in .gitignore instead: `!.geniro/actions/` plus `!.geniro/actions/**`.
#
# The one check kept from block-geniro-deletion.sh, which was deleted on
# 2026-09-29 together with the other command-string guards (HOOKS.md §Removed
# guards). It stays deliberately literal: it reads the command as written and
# does not follow variables, `bash -c` payloads, or interpreter calls — the
# deleted guards chased those and blocked read-only commands far more often
# than they caught a real write. The guard keys on tool_input.command alone, so
# every tool that runs a shell command (Bash, Monitor) is checked the same way.
#
# tests/hooks/block-geniro-force-add.sh runs each spelling through real git and
# requires this guard to block exactly when git stages an ignored .geniro/ file.
#
# Bypass: add "git-add-force-geniro" to allow_patterns in .geniro/safety.json.

set -uo pipefail

INPUT=$(cat)

if ! command -v jq >/dev/null 2>&1; then
  printf '{"systemMessage":"Geniro force-add guard inactive: jq not found on PATH, so git add -f on .geniro/ is NOT being checked. Install jq to restore it."}\n'
  exit 0
fi

COMMAND=$(printf '%s' "$INPUT" | jq -r '.tool_input.command // ""' 2>/dev/null || true)

# Nothing to check unless both words appear. -i: macOS resolves `GIT` like
# `git`, and `.GENIRO` is the same directory on a case-insensitive filesystem.
grep -qi 'git' <<< "$COMMAND" || exit 0
grep -qi '\.geniro' <<< "$COMMAND" || exit 0

# Heredoc bodies are data (a handoff that MENTIONS the rule is not a force-add),
# so drop them. The whole delimiter word counts (`<<END-NOTE` closes on
# `END-NOTE`), quoted and backslashed forms included, and several heredocs on one
# line close in order. A `<<` that never finds its closing line — an arithmetic
# shift, a `<<EOF` quoted inside prose — drops nothing: its lines are scanned.
# (No apostrophes in the awk text: it sits inside a single-quoted shell string.)
strip_heredocs() {
  awk -v sq="'" -v dq='"' '
    function unq(s,   out, i, c) {
      out = ""
      for (i = 1; i <= length(s); i++) {
        c = substr(s, i, 1)
        if (c != "\\" && c != sq && c != dq) out = out c
      }
      return out
    }
    function register(rest,   m, after, c, i, tag) {
      while (match(rest, /<<-?/)) {
        m = substr(rest, RSTART, RLENGTH)
        after = substr(rest, RSTART + RLENGTH)
        if (substr(after, 1, 1) == "<") { rest = substr(after, 2); continue }
        sub(/^[ \t]*/, "", after)
        c = substr(after, 1, 1)
        tag = ""
        if (c == sq || c == dq) {
          after = substr(after, 2)
          i = index(after, c)
          if (i == 0) { tag = after; after = "" }
          else { tag = substr(after, 1, i - 1); after = substr(after, i + 1) }
        } else if (match(after, /^[^ \t;&|()<>]+/)) {
          tag = unq(substr(after, 1, RLENGTH))
          after = substr(after, RLENGTH + 1)
        }
        if (tag != "") { nq++; tags[nq] = tag; strips[nq] = (m == "<<-") }
        rest = after
      }
    }
    cur > 0 {
      buf[++nbuf] = $0
      t = $0
      if (strips[cur]) sub(/^\t+/, "", t)
      if (t == tags[cur]) {
        cur++
        nbuf = 0
        if (cur > nq) { cur = 0; nq = 0 }
      }
      next
    }
    {
      print
      nq = 0
      register($0)
      if (nq > 0) { cur = 1; nbuf = 0 }
    }
    END { if (cur > 0) for (k = 1; k <= nbuf; k++) print buf[k] }
  '
}

# Then join backslash-newline continuations, normalise pathspec magic, and blank
# quoted spans that contain whitespace — prose such as a commit message — while a
# whitespace-free quoted path (`".geniro/x"`) survives. A quoted span may not
# cross ; & | so two stray apostrophes cannot swallow a live command between them.
# Pathspec magic `:(top)` / `:(top,glob)` is folded to a bare `:` first (and
# `:(exclude)` to `:!`, which names nothing): its parentheses would otherwise
# split the path from its `.geniro`, and a space inside the quotes would blank it.
SCANNED=$(printf '%s\n' "$COMMAND" | strip_heredocs \
  | awk '{ if (sub(/\\$/, "")) printf "%s ", $0; else print }' \
  | sed -E "s/:\([^)]*exclude[^)]*\)/:!/g; s/:\([^)]*\)/:/g; s/\"[^\";&|]*[[:space:]][^\";&|]*\"/\"\"/g; s/'[^';&|]*[[:space:]][^';&|]*'/''/g")

find_safety_json() {
  local dir="$PWD"
  while [ "$dir" != "/" ]; do
    [ -f "$dir/.geniro/safety.json" ] && { echo "$dir/.geniro/safety.json"; return 0; }
    dir=$(dirname "$dir")
  done
  # A linked worktree never carries the gitignored .geniro/ — fall back to the
  # main checkout, which prints its common dir as an absolute `<main>/.git`.
  dir=$(git rev-parse --git-common-dir 2>/dev/null) || return 1
  case "$dir" in
    /*/.git) [ -f "${dir%/.git}/.geniro/safety.json" ] && { echo "${dir%/.git}/.geniro/safety.json"; return 0; } ;;
  esac
  return 1
}

# Words that run another command as their argument: a `git` after one is still
# the invocation (`sudo -u root git add …`, `xargs git add …`).
WRAPPERS=" sudo doas env command builtin exec eval time nohup nice ionice setsid stdbuf timeout xargs noglob unbuffer caffeinate "
# `--force` is git add's only long option starting with `f`, so every
# unambiguous prefix (`--f` … `--forc`) is the same flag.
RE_FORCE='^-[a-zA-Z]*f[a-zA-Z]*$|^--f(o(r(c(e)?)?)?)?$'
RE_ASSIGN='^[a-z_][a-z0-9_]*\+?='
RE_REDIR_BARE='^[0-9]*(>>|>|<)$'
RE_REDIR_ATTACHED='^[0-9]*(>>|>|<)'
# A `.geniro` path component: leading, after a slash, after pathspec magic's
# `:`, or after the `,` of `--cacheinfo mode,sha,path`.
RE_GENIRO='(^|[/:,])\.geniro(/|$)'

# The word as the shell reads it: lowercase, quotes and backslashes removed.
norm_word() { printf '%s' "${1:-}" | tr '[:upper:]' '[:lower:]' | tr -d "\"'\\\\"; }

names_geniro() { local w; w=$(norm_word "${1:-}"); [[ $w =~ $RE_GENIRO ]]; }

# <token> <option> <min-length>: the token is the option, or an unambiguous
# prefix of it (git's parse-options accepts both).
is_long_opt() {
  local t="${1:-}" full="${2:-}" min="${3:-0}"
  [ "${#t}" -ge "$min" ] && [ "${#t}" -le "${#full}" ] && [ "${full:0:${#t}}" = "$t" ]
}

# The update-index flags that put a path in the index with no ignore check
# (git rejects `--force` there, so it is not one of them).
is_staging_flag() {
  is_long_opt "${1:-}" --add 4 || is_long_opt "${1:-}" --cacheinfo 4 || is_long_opt "${1:-}" --index-info 5
}

# Returns 0 when one command segment force-adds a .geniro/ path.
segment_force_adds_geniro() {
  local -a toks
  read -r -a toks <<< "$1"
  local i=0 n=${#toks[@]} word base wrapped=0
  # Locate the git word in command position: past assignments, redirections,
  # shell keywords and wrapper commands, and nowhere else — `echo git add -f …`
  # only prints the words.
  while [ "$i" -lt "$n" ]; do
    word=$(norm_word "${toks[$i]}")
    base=${word##*/}
    if [ -z "$word" ]; then
      i=$((i + 1)); continue
    fi
    case "$word" in
      '!'|'{'|if|then|elif|else|while|until|do) i=$((i + 1)); continue ;;
    esac
    if [[ $word =~ $RE_ASSIGN ]] || [[ $word =~ $RE_REDIR_ATTACHED && ! $word =~ $RE_REDIR_BARE ]]; then
      i=$((i + 1)); continue
    fi
    if [[ $word =~ $RE_REDIR_BARE ]]; then
      i=$((i + 2)); continue
    fi
    [ "$base" = "git" ] && break
    case "$WRAPPERS" in
      *" $base "*) wrapped=1; i=$((i + 1)); continue ;;
    esac
    if [ "$wrapped" -eq 1 ]; then
      i=$((i + 1)); continue
    fi
    return 1
  done
  [ "$i" -lt "$n" ] || return 1
  i=$((i + 1))
  # Skip git's global options. -C, --work-tree and --git-dir move where a later
  # relative path lands, so their value can be the .geniro directory itself
  # (`git -C .geniro add -f actions/x.md`); the other options only take a value.
  local geniro=0 tok val
  while [ "$i" -lt "$n" ]; do
    tok=${toks[$i]}
    case "$tok" in
      -C|--git-dir|--work-tree)
        val=${toks[$((i + 1))]:-}
        names_geniro "$val" && geniro=1
        i=$((i + 2)) ;;
      --git-dir=*|--work-tree=*)
        names_geniro "${tok#*=}" && geniro=1
        i=$((i + 1)) ;;
      -c|--namespace|--super-prefix|--config-env) i=$((i + 2)) ;;
      -*) i=$((i + 1)) ;;
      *) break ;;
    esac
  done
  [ "$i" -lt "$n" ] || return 1
  local mode
  case "$(norm_word "${toks[$i]}")" in
    add|stage) mode=add ;;
    update-index) mode=index ;;
    *) return 1 ;;
  esac
  i=$((i + 1))
  local forced=0 opts=1
  while [ "$i" -lt "$n" ]; do
    tok=${toks[$i]}
    if [ "$opts" -eq 1 ] && [ "$tok" = "--" ]; then
      opts=0
    elif [ "$opts" -eq 1 ] && [ "$mode" = add ] && [[ $tok =~ $RE_FORCE ]]; then
      forced=1
    elif [ "$opts" -eq 1 ] && [ "$mode" = index ] && is_staging_flag "$tok"; then
      forced=1
    else
      names_geniro "$tok" && geniro=1
    fi
    i=$((i + 1))
  done
  [ "$forced" -eq 1 ] && [ "$geniro" -eq 1 ]
}

while IFS= read -r SEGMENT; do
  [ -z "$SEGMENT" ] && continue
  segment_force_adds_geniro "$SEGMENT" || continue
  SAFETY_FILE=$(find_safety_json 2>/dev/null || true)
  if [ -n "$SAFETY_FILE" ] && jq -e '(.allow_patterns // []) | index("git-add-force-geniro")' "$SAFETY_FILE" >/dev/null 2>&1; then
    exit 0
  fi
  {
    echo "Geniro safety blocked [git-add-force-geniro]: git add -f on .geniro/ paths puts ignored files in the IDE's Source Control panel, where one 'Discard All Changes' click deletes them."
    echo "Track a .geniro/ subdir by negating it in .gitignore instead (e.g. \`!.geniro/actions/\` and \`!.geniro/actions/**\`), then use a plain \`git add\`."
    if [ -n "$SAFETY_FILE" ]; then
      echo "To allow it anyway, add \"git-add-force-geniro\" to allow_patterns in $SAFETY_FILE"
    else
      echo "To allow it anyway, create .geniro/safety.json with: {\"allow_patterns\": [\"git-add-force-geniro\"]}"
    fi
  } >&2
  exit 2
done <<< "$(printf '%s\n' "$SCANNED" | tr ';&|()`' '\n\n\n\n\n\n')"

exit 0
